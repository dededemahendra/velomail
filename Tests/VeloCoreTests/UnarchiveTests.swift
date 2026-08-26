import Testing
import Foundation
@testable import VeloCore

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@Suite struct UnarchiveTests {
    private func makeContext() throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        return (OutboundService(writer: NoopWriter(), store: store, mutations: mutations,
                                identity: "me@x.com", now: { Date(timeIntervalSince1970: 1) }),
                store, mutations)
    }

    private func seed(_ store: MailStore) throws {
        try store.upsert(MailThread(id: "t", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: false, labelIDs: ["INBOX"]))
    }

    @Test func unarchivingPutsAThreadBackInTheInbox() throws {
        let (service, store, _) = try makeContext()
        try seed(store)
        try service.archive(threadID: "t")
        #expect(try store.inboxThreads().isEmpty)

        try service.unarchive(threadID: "t")

        #expect(try store.inboxThreads().map(\.id) == ["t"])
    }

    @Test func undeletingClearsTrashAsWellAsRestoringInbox() throws {
        let (service, store, _) = try makeContext()
        try seed(store)
        try service.trash(threadID: "t")

        try service.unarchive(threadID: "t")

        // Leaving TRASH behind would put it back in the inbox *and* the bin.
        let labels = try #require(try store.thread(id: "t")?.labelIDs)
        #expect(labels.contains("INBOX"))
        #expect(!labels.contains("TRASH"))
    }

    @Test func undoingQueuesTheChangeLikeAnythingElse() throws {
        let (service, store, mutations) = try makeContext()
        try seed(store)
        try service.archive(threadID: "t")

        try service.unarchive(threadID: "t")

        // It has to reach Gmail too, or the thread reappears locally and stays
        // archived everywhere else.
        #expect(try mutations.all().map(\.kind).contains(.unarchive))
    }

    @Test func unarchivingSomethingAlreadyInTheInboxIsHarmless() throws {
        let (service, store, _) = try makeContext()
        try seed(store)

        try service.unarchive(threadID: "t")

        #expect(try store.inboxThreads().map(\.id) == ["t"])
    }

    @Test func unarchivingAnUnknownThreadIsANoOp() throws {
        let (service, _, mutations) = try makeContext()
        try service.unarchive(threadID: "nope")
        #expect(try mutations.all().isEmpty)
    }
}
