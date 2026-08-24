import Testing
import Foundation
@testable import VeloCore

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@Suite struct SnoozeTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func makeContext() throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let service = OutboundService(writer: NoopWriter(), store: store, mutations: mutations,
                                      identity: "me@x.com", now: { Date(timeIntervalSince1970: 1_000_000) })
        return (service, store, mutations)
    }

    private func seed(_ store: MailStore, id: String = "t") throws {
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: false, labelIDs: ["INBOX"]))
    }

    @Test func threadTableHasASnoozedUntilColumn() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let columns = try db.columns(in: "thread").map(\.name)
            #expect(columns.contains("snoozedUntil"))
        }
    }

    @Test func snoozingHidesTheThreadFromTheInbox() throws {
        let (service, store, _) = try makeContext()
        try seed(store)

        try service.snooze(threadID: "t", until: epoch.addingTimeInterval(3_600))

        #expect(try store.inboxThreads(now: epoch).isEmpty)
    }

    @Test func snoozingRemovesInboxSoItSyncsToEveryDevice() throws {
        let (service, store, mutations) = try makeContext()
        try seed(store)

        try service.snooze(threadID: "t", until: epoch.addingTimeInterval(3_600))

        #expect(try mutations.pending().first?.kind == .snooze)
        #expect(try store.thread(id: "t")?.labelIDs.contains("INBOX") == false)
    }

    @Test func aSnoozedThreadReappearsOnceItsTimeArrives() throws {
        let (service, store, _) = try makeContext()
        try seed(store)
        try service.snooze(threadID: "t", until: epoch.addingTimeInterval(3_600))

        let woken = try service.wakeSnoozed(now: epoch.addingTimeInterval(3_600))

        #expect(woken == ["t"])
        #expect(try store.inboxThreads(now: epoch.addingTimeInterval(3_600)).map(\.id) == ["t"])
    }

    @Test func wakingIsANoOpBeforeTheTime() throws {
        let (service, store, _) = try makeContext()
        try seed(store)
        try service.snooze(threadID: "t", until: epoch.addingTimeInterval(3_600))

        #expect(try service.wakeSnoozed(now: epoch.addingTimeInterval(60)).isEmpty)
        #expect(try store.inboxThreads(now: epoch.addingTimeInterval(60)).isEmpty)
    }

    @Test func wakingClearsTheSnoozeSoItDoesNotWakeTwice() throws {
        let (service, store, _) = try makeContext()
        try seed(store)
        try service.snooze(threadID: "t", until: epoch)

        _ = try service.wakeSnoozed(now: epoch)

        #expect(try store.thread(id: "t")?.snoozedUntil == nil)
        #expect(try service.wakeSnoozed(now: epoch).isEmpty)
    }

    @Test func wakingQueuesTheInboxLabelBack() throws {
        let (service, store, mutations) = try makeContext()
        try seed(store)
        try service.snooze(threadID: "t", until: epoch)

        _ = try service.wakeSnoozed(now: epoch)

        #expect(try mutations.pending().map(\.kind) == [.snooze, .unsnooze])
        #expect(try store.thread(id: "t")?.labelIDs.contains("INBOX") == true)
    }

    @Test func snoozingAnUnknownThreadIsANoOp() throws {
        let (service, _, mutations) = try makeContext()
        try service.snooze(threadID: "nope", until: epoch)
        #expect(try mutations.all().isEmpty)
    }

    @Test func onlyDueThreadsWake() throws {
        let (service, store, _) = try makeContext()
        try seed(store, id: "soon")
        try seed(store, id: "later")
        try service.snooze(threadID: "soon", until: epoch.addingTimeInterval(60))
        try service.snooze(threadID: "later", until: epoch.addingTimeInterval(86_400))

        #expect(try service.wakeSnoozed(now: epoch.addingTimeInterval(60)) == ["soon"])
    }

    @Test func anUnsnoozedThreadIsUnaffectedByTheInboxTimeFilter() throws {
        let (_, store, _) = try makeContext()
        try seed(store)
        #expect(try store.inboxThreads(now: epoch).map(\.id) == ["t"])
    }
}
