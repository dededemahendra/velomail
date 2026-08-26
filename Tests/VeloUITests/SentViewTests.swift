import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct SentViewTests {
    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try seed(store, id: "in", labels: ["INBOX"], sender: "Alice <alice@x.com>",
                 recipients: ["me@x.com"], at: 10)
        try seed(store, id: "out", labels: ["SENT"], sender: "me@x.com",
                 recipients: ["Bob <bob@x.com>"], at: 20)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, store)
    }

    private func seed(_ store: MailStore, id: String, labels: [String], sender: String,
                      recipients: [String], at seconds: TimeInterval) throws {
        let date = Date(timeIntervalSince1970: seconds)
        try store.upsert(MailThread(id: id, sender: sender, snippet: "s", lastMessageDate: date,
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: sender,
                                 recipients: recipients, subject: "s", date: date,
                                 bodyHTML: nil, bodyText: "b", isUnread: false, labelIDs: labels))
    }

    // MARK: - Getting there

    @Test func theListStartsOnTheInbox() throws {
        let (app, _) = try makeApp()
        #expect(app.inbox.scope == .inbox)
        #expect(app.inbox.threads.map(\.id) == ["in"])
    }

    @Test func gSShowsWhatWasSent() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))

        #expect(app.inbox.scope == .sent)
        #expect(app.inbox.threads.map(\.id) == ["out"])
        #expect(app.route == .list)
    }

    @Test func gIComesBack() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("i")))

        #expect(app.inbox.scope == .inbox)
        #expect(app.inbox.threads.map(\.id) == ["in"])
    }

    @Test func theCursorStartsAtTheTopOfTheNewList() throws {
        // Carrying a row index across two different lists would land the cursor
        // on whatever happens to sit in that position.
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))

        #expect(app.inbox.selectedIndex == 0)
    }

    // MARK: - What it shows

    @Test func sentRowsNameTheRecipient() throws {
        // "me" on every row tells the writer nothing. In Sent the useful name
        // is who it went to.
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))

        #expect(app.inbox.correspondent(of: try #require(app.inbox.threads.first)) == "Bob")
    }

    @Test func inboxRowsStillNameTheSender() throws {
        let (app, _) = try makeApp()
        #expect(app.inbox.correspondent(of: try #require(app.inbox.threads.first)) == "Alice")
    }

    @Test func twoRecipientsReadAsOneOther() throws {
        let (app, store) = try makeApp()
        try seed(store, id: "pair", labels: ["SENT"], sender: "me@x.com",
                 recipients: ["Bob <bob@x.com>", "carol@x.com"], at: 30)
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))

        #expect(app.inbox.correspondent(of: try #require(app.inbox.threads.first))
                == "Bob and 1 other")
    }

    @Test func severalRecipientsAreSummarised() throws {
        let (app, store) = try makeApp()
        try seed(store, id: "many", labels: ["SENT"], sender: "me@x.com",
                 recipients: ["Bob <bob@x.com>", "carol@x.com", "d@x.com"], at: 30)
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))

        #expect(app.inbox.correspondent(of: try #require(app.inbox.threads.first))
                == "Bob and 2 others")
    }

    @Test func theSentListIsTitled() throws {
        let (app, _) = try makeApp()
        #expect(app.inbox.title == "Inbox")
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("s")))
        #expect(app.inbox.title == "Sent")
    }
}
