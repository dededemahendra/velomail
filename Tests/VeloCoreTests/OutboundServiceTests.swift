import Testing
import Foundation
import GRDB
@testable import VeloCore

/// Writer stub — B4 exercises optimistic apply only, so modify is never called.
private struct UnusedWriter: GmailWriting {
    func modifyMessage(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessageDTO {
        fatalError("modify not called during optimistic apply")
    }
}

@Suite struct OutboundServiceTests {
    private func makeContext(now: @escaping () -> Date = { Date(timeIntervalSince1970: 42) })
        throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let service = OutboundService(writer: UnusedWriter(), store: store, mutations: mutations, now: now)
        return (service, store, mutations)
    }

    private func seedThread(_ store: MailStore, id: String, labels: [String], unread: Bool,
                            messageIDs: [String]) throws {
        try store.upsert(MailThread(id: id, snippet: id, lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: unread, hasAttachments: false, labelIDs: labels))
        for (i, mid) in messageIDs.enumerated() {
            try store.upsert(Message(id: mid, threadID: id, sender: "x", recipients: [], subject: "",
                                     date: Date(timeIntervalSince1970: TimeInterval(i)),
                                     bodyHTML: nil, bodyText: nil, isUnread: unread))
        }
    }

    private func payload(_ mutation: PendingMutation) throws -> OutboundMutationPayload {
        try JSONDecoder().decode(OutboundMutationPayload.self, from: mutation.payload)
    }

    @Test func archiveRemovesInboxLocallyAndEnqueues() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1", "m2"])

        try service.archive(threadID: "t")

        #expect(try store.inboxThreads().isEmpty)
        let pending = try mutations.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .archive)
        let p = try payload(pending[0])
        #expect(p.removeLabelIDs == ["INBOX"])
        #expect(p.addLabelIDs == [])
        #expect(p.messageIDs == ["m1", "m2"])
        #expect(p.previousLabelIDs.contains("INBOX"))
    }

    @Test func markReadClearsUnreadLocallyAndEnqueues() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX", "UNREAD"], unread: true, messageIDs: ["m1"])

        try service.markRead(threadID: "t")

        #expect(try store.thread(id: "t")?.isUnread == false)
        let p = try payload(try mutations.pending()[0])
        #expect(p.removeLabelIDs == ["UNREAD"])
        #expect(try mutations.pending()[0].kind == .markRead)
    }

    @Test func markUnreadSetsUnreadLocallyAndEnqueues() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.markUnread(threadID: "t")

        #expect(try store.thread(id: "t")?.isUnread == true)
        let p = try payload(try mutations.pending()[0])
        #expect(p.addLabelIDs == ["UNREAD"])
        #expect(try mutations.pending()[0].kind == .markUnread)
    }

    @Test func archivePreservesUnreadFlag() async throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX", "UNREAD"], unread: true, messageIDs: ["m1"])

        try service.archive(threadID: "t")

        let updated = try store.thread(id: "t")
        #expect(updated?.labelIDs == ["UNREAD"])
        #expect(updated?.isUnread == true)
    }

    @Test func unknownThreadIsNoOp() async throws {
        let (service, _, mutations) = try makeContext()
        try service.archive(threadID: "ghost")
        #expect(try mutations.pending().isEmpty)
    }

    @Test func createdAtUsesInjectedClock() async throws {
        let fixed = Date(timeIntervalSince1970: 777)
        let (service, store, mutations) = try makeContext(now: { fixed })
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.archive(threadID: "t")

        #expect(try mutations.pending()[0].createdAt == fixed)
    }
}
