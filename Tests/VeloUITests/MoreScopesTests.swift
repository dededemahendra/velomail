import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct MoreScopesTests {
    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try seed(store, id: "inbox", labels: ["INBOX"], at: 40)
        try seed(store, id: "star", labels: ["INBOX", "STARRED"], at: 30)
        try seed(store, id: "filed", labels: [], at: 20)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, store)
    }

    private func seed(_ store: MailStore, id: String, labels: [String], at seconds: TimeInterval) throws {
        let date = Date(timeIntervalSince1970: seconds)
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s", lastMessageDate: date,
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: "a@b.com", recipients: [],
                                 subject: "s", date: date, bodyHTML: nil, bodyText: "b",
                                 isUnread: false, labelIDs: labels))
    }

    @Test func gStarShowsStarredThreads() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("t")))

        #expect(app.inbox.scope == .starred)
        #expect(app.inbox.threads.map(\.id) == ["star"])
        #expect(app.inbox.title == "Starred")
    }

    @Test func gAShowsWhatWasFiledAway() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("e")))

        #expect(app.inbox.scope == .archive)
        #expect(app.inbox.threads.map(\.id) == ["filed"])
        #expect(app.inbox.title == "Archive")
    }

    @Test func archivingFromTheInboxMovesItToTheArchive() throws {
        // The two views have to agree, or archiving looks like deleting.
        // Whichever row the cursor lands on -- the list groups, so that is not
        // the same as the newest thread.
        let (app, _) = try makeApp()
        let archived = try #require(app.inbox.selectedThread?.id)
        app.handle(KeyInput(.character("e")))

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("e")))

        #expect(app.inbox.threads.map(\.id).contains(archived))
    }

    @Test func starringPutsAThreadInTheStarredList() throws {
        let (app, _) = try makeApp()
        // A thread that is not already starred, so `s` stars rather than unstars.
        app.inbox.select(index: try #require(
            app.inbox.threads.firstIndex { !$0.labelIDs.contains("STARRED") }))
        let starred = try #require(app.inbox.selectedThread?.id)
        app.handle(KeyInput(.character("s")))

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("t")))

        #expect(app.inbox.threads.map(\.id).contains(starred))
    }

    @Test func bothAreInTheCommandPalette() throws {
        let titles = CommandRegistry.v1.commands.map(\.title)
        #expect(titles.contains("Go to Starred"))
        #expect(titles.contains("Go to Archive"))
    }

    @Test func everyScopeHasAnEmptyStateOfItsOwn() throws {
        // A Starred list saying "Inbox zero" is worse than saying nothing.
        for scope in [MailScope.inbox, .sent, .snoozed, .starred, .archive] {
            #expect(!EmptyListView(scope: scope).headline.isEmpty)
        }
    }
}
