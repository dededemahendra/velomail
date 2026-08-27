import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct UnreadCountTests {
    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        return (app, store)
    }

    private func seed(_ store: MailStore, id: String, labels: [String], unread: Bool) throws {
        let date = Date(timeIntervalSince1970: 100)
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s", lastMessageDate: date,
                                    isUnread: unread, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: "a@b.com", recipients: [],
                                 subject: "s", date: date, bodyHTML: nil, bodyText: "b",
                                 isUnread: unread, labelIDs: labels))
    }

    @Test func aListSaysHowMuchIsWaiting() throws {
        // Otherwise every list has to be visited to find out whether it is
        // worth visiting.
        let (app, store) = try makeApp()
        try seed(store, id: "a", labels: ["INBOX"], unread: true)
        try seed(store, id: "b", labels: ["INBOX"], unread: false)
        try app.start()

        #expect(app.unreadCount(in: .inbox) == 1)
    }

    @Test func eachListCountsItsOwn() throws {
        let (app, store) = try makeApp()
        try seed(store, id: "in", labels: ["INBOX"], unread: true)
        try seed(store, id: "star", labels: ["STARRED"], unread: true)
        try app.start()

        #expect(app.unreadCount(in: .inbox) == 1)
        #expect(app.unreadCount(in: .starred) == 1)
        #expect(app.unreadCount(in: .sent) == 0)
    }

    @Test func aListWithNothingWaitingSaysZero() throws {
        let (app, store) = try makeApp()
        try seed(store, id: "a", labels: ["INBOX"], unread: false)
        try app.start()

        #expect(app.unreadCount(in: .inbox) == 0)
    }

    @Test func focusModeHidesTheCountsToo() throws {
        // Focus exists to stop the app telling you how much is waiting. A
        // number beside every list would be exactly that.
        let (app, store) = try makeApp()
        try seed(store, id: "a", labels: ["INBOX"], unread: true)
        try app.start()

        app.toggleFocus()

        #expect(app.unreadCount(in: .inbox) == 0)
    }

    @Test func thePaletteSaysWhatIsWaitingWhereItIsGoing() throws {
        let (app, store) = try makeApp()
        try seed(store, id: "a", labels: ["INBOX"], unread: true)
        try seed(store, id: "b", labels: ["INBOX"], unread: true)
        try app.start()

        #expect(app.palette.commands.contains { $0.title == "Go to Inbox (2)" })
    }

    @Test func anEmptyListIsNotAdvertisedWithAZero() throws {
        // "Go to Sent (0)" is noise on every list that is quiet.
        let (app, store) = try makeApp()
        try seed(store, id: "a", labels: ["INBOX"], unread: false)
        try app.start()

        #expect(app.palette.commands.contains { $0.title == "Go to Inbox" })
    }
}
