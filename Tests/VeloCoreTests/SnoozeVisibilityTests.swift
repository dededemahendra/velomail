import Testing
import Foundation
@testable import VeloCore

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@Suite struct SnoozeVisibilityTests {
    private func makeContext() throws -> (OutboundService, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let service = OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com")
        return (service, store)
    }

    private func seed(_ store: MailStore, id: String) throws {
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 10),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: "a@b.com",
                                 recipients: [], subject: "s",
                                 date: Date(timeIntervalSince1970: 10), bodyHTML: nil,
                                 bodyText: "b", isUnread: false, labelIDs: ["INBOX"]))
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Seeing it

    @Test func aSnoozedThreadCanBeListed() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t")
        try service.snooze(threadID: "t", until: now.addingTimeInterval(3_600))

        #expect(try store.snoozedThreads(now: now).map(\.id) == ["t"])
        #expect(try store.inboxThreads(now: now).isEmpty)
    }

    @Test func theSoonestToWakeComesFirst() throws {
        // The list answers "what is coming back", so the order is the order it
        // comes back in, not the order it arrived.
        let (service, store) = try makeContext()
        try seed(store, id: "late")
        try seed(store, id: "soon")
        try service.snooze(threadID: "late", until: now.addingTimeInterval(90_000))
        try service.snooze(threadID: "soon", until: now.addingTimeInterval(3_600))

        #expect(try store.snoozedThreads(now: now).map(\.id) == ["soon", "late"])
    }

    @Test func aThreadPastItsWakeTimeIsNoLongerSnoozed() throws {
        // It belongs to the inbox again; showing it in both would double-count.
        let (service, store) = try makeContext()
        try seed(store, id: "t")
        try service.snooze(threadID: "t", until: now.addingTimeInterval(-1))

        #expect(try store.snoozedThreads(now: now).isEmpty)
    }

    // MARK: - Taking it back

    @Test func unsnoozingPutsItBackInTheInboxNow() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t")
        try service.snooze(threadID: "t", until: now.addingTimeInterval(90_000))

        try service.unsnooze(threadID: "t")

        #expect(try store.inboxThreads(now: now).map(\.id) == ["t"])
        #expect(try store.snoozedThreads(now: now).isEmpty)
    }

    @Test func unsnoozingClearsTheWakeTime() throws {
        // Left set, the waker would fire on a thread already back in the inbox.
        let (service, store) = try makeContext()
        try seed(store, id: "t")
        try service.snooze(threadID: "t", until: now.addingTimeInterval(90_000))

        try service.unsnooze(threadID: "t")

        #expect(try store.thread(id: "t")?.snoozedUntil == nil)
    }

    @Test func unsnoozingSomethingNotSnoozedChangesNothing() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t")

        try service.unsnooze(threadID: "t")

        #expect(try store.inboxThreads(now: now).map(\.id) == ["t"])
    }
}
