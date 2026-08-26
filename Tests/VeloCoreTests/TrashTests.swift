import Testing
import Foundation
@testable import VeloCore

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@Suite struct TrashTests {
    private func makeContext() throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        return (OutboundService(writer: NoopWriter(), store: store, mutations: mutations,
                                identity: "me@x.com", now: { Date(timeIntervalSince1970: 1) }),
                store, mutations)
    }

    private func seed(_ store: MailStore, unread: Bool = true) throws {
        let labels = unread ? ["INBOX", "UNREAD"] : ["INBOX"]
        try store.upsert(MailThread(id: "t", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: unread, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: unread, labelIDs: labels))
    }

    // MARK: - Trash

    @Test func trashingMovesTheThreadOutOfTheInbox() throws {
        let (service, store, _) = try makeContext()
        try seed(store)

        try service.trash(threadID: "t")

        #expect(try store.inboxThreads().isEmpty)
    }

    @Test func trashingAppliesGmailsTrashLabel() throws {
        let (service, store, mutations) = try makeContext()
        try seed(store)

        try service.trash(threadID: "t")

        // TRASH is what makes it recoverable from any client, rather than a
        // local disappearance nothing else knows about.
        #expect(try store.thread(id: "t")?.labelIDs.contains("TRASH") == true)
        #expect(try mutations.pending().first?.kind == .trash)
    }

    @Test func trashingIsDistinctFromArchiving() throws {
        let (service, store, _) = try makeContext()
        try seed(store)

        try service.trash(threadID: "t")

        // Archive removes INBOX and stops there; trash also says where it went.
        let labels = try #require(try store.thread(id: "t")?.labelIDs)
        #expect(!labels.contains("INBOX"))
        #expect(labels.contains("TRASH"))
    }

    @Test func trashingAnUnknownThreadIsANoOp() throws {
        let (service, _, mutations) = try makeContext()
        try service.trash(threadID: "nope")
        #expect(try mutations.all().isEmpty)
    }

    // MARK: - Mark unread

    @Test func markingUnreadPutsTheFlagBack() throws {
        let (service, store, _) = try makeContext()
        try seed(store, unread: false)

        try service.markUnread(threadID: "t")

        #expect(try store.thread(id: "t")?.isUnread == true)
        #expect(try store.thread(id: "t")?.labelIDs.contains("UNREAD") == true)
    }

    @Test func markingUnreadLeavesItInTheInbox() throws {
        let (service, store, _) = try makeContext()
        try seed(store, unread: false)

        try service.markUnread(threadID: "t")

        // The whole point is to come back to it later.
        #expect(try store.inboxThreads().map(\.id) == ["t"])
    }

    @Test func markingUnreadQueuesTheChange() throws {
        let (service, store, mutations) = try makeContext()
        try seed(store, unread: false)

        try service.markUnread(threadID: "t")

        #expect(try mutations.pending().first?.kind == .markUnread)
    }
}
