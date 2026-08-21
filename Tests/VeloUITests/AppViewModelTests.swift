import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct AppViewModelTests {
    private func makeApp(configured: Bool = true, threadCount: Int = 3) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        for i in 0..<threadCount {
            let id = "t\(i)"
            try store.upsert(MailThread(id: id, snippet: "s\(i)",
                                        lastMessageDate: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                        isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
            try store.upsert(Message(id: "m\(i)", threadID: id, sender: "a@b.com", recipients: ["me@x.com"],
                                     subject: "subject \(i)", date: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                     bodyHTML: nil, bodyText: "body \(i)", isUnread: false, labelIDs: ["INBOX"]))
        }
        let outbound = OutboundService(writer: NoopWriter(), store: store, mutations: mutations,
                                       identity: "me@x.com")
        let config = AppConfig.resolve(
            environment: configured ? ["VELOMAIL_CLIENT_ID": "cid"] : [:], configFile: nil)
        let app = AppViewModel(config: config, store: store, outbound: outbound,
                               identity: "me@x.com", isSignedIn: true)
        try app.start()
        return app
    }

    private func press(_ app: AppViewModel, _ key: Character) {
        app.handle(KeyInput(.character(key)))
    }

    @Test func startsInSetupWhenUnconfigured() throws {
        #expect(try makeApp(configured: false).route == .setup)
    }

    @Test func startsInTheListWhenConfigured() throws {
        #expect(try makeApp().route == .list)
    }

    @Test func openSelectedRoutesToTheThreadView() throws {
        let app = try makeApp()
        press(app, "o")
        #expect(app.route == .thread)
    }

    @Test func backFromTheThreadReturnsToTheList() throws {
        let app = try makeApp()
        press(app, "o")
        app.handle(KeyInput(.escape))
        #expect(app.route == .list)
    }

    @Test func composeRoutesToCompose() throws {
        let app = try makeApp()
        press(app, "c")
        #expect(app.route == .compose)
    }

    @Test func theCommandPaletteOpensAndClosesOnBack() throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("k"), [.command]))
        #expect(app.route == .palette)
        app.handle(KeyInput(.escape))
        #expect(app.route == .list)
    }

    @Test func navigationKeysMoveTheInboxSelection() throws {
        let app = try makeApp()
        press(app, "j")
        #expect(app.inbox.selectedThread?.id == "t1")
        press(app, "k")
        #expect(app.inbox.selectedThread?.id == "t0")
    }

    @Test func archiveIsDispatchedToTheInboxViewModel() throws {
        let app = try makeApp()
        press(app, "e")
        #expect(app.inbox.threads.map(\.id) == ["t1", "t2"])
        #expect(app.inbox.selectedThread?.id == "t1")
    }

    @Test func goToInboxChordReturnsToTheListFromAThread() throws {
        let app = try makeApp()
        press(app, "o")
        press(app, "g")
        press(app, "i")
        #expect(app.route == .list)
    }

    @Test func keystrokesAreIgnoredWhileComposing() throws {
        let app = try makeApp()
        press(app, "c")

        // Typing "e" in a compose field must not archive the inbox behind it.
        press(app, "e")

        #expect(app.route == .compose)
        #expect(app.inbox.threads.count == 3)
    }

    @Test func escapeLeavesCompose() throws {
        let app = try makeApp()
        press(app, "c")
        app.handle(KeyInput(.escape))
        #expect(app.route == .list)
    }

    @Test func handleReportsWhetherItConsumedTheEvent() throws {
        let app = try makeApp()
        // Unbound keys must fall through so text fields still receive them.
        #expect(app.handle(KeyInput(.character("z"))) == false)
        #expect(app.handle(KeyInput(.character("j"))) == true)
    }

    @Test func openingAThreadMarksItRead() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t", snippet: "s", lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: true, hasAttachments: false, labelIDs: ["INBOX", "UNREAD"]))
        try store.upsert(Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: true, labelIDs: ["INBOX", "UNREAD"]))
        let app = AppViewModel(config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
                               store: store,
                               outbound: OutboundService(writer: NoopWriter(), store: store,
                                                         mutations: MutationStore(db), identity: "me@x.com"),
                               identity: "me@x.com", isSignedIn: true)
        try app.start()

        app.handle(KeyInput(.character("o")))

        #expect(app.inbox.selectedThread?.isUnread == false)
    }

    @Test func configuredButSignedOutRoutesToSignIn() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "cid"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: NoopWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: false)
        try app.start()

        // Credentials present but no token yet: ask the user to sign in rather
        // than showing an empty inbox that will never fill.
        #expect(app.route == .signIn)
    }

    @Test func signingInMovesToTheList() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "cid"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: NoopWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: false)
        try app.start()

        app.setSignedIn(true)

        #expect(app.route == .list)
    }

    @Test func unconfiguredStillWinsOverSignIn() throws {
        // No credentials at all: setup instructions come first; there is nothing
        // to sign in *to* yet.
        #expect(try makeApp(configured: false).route == .setup)
    }
}

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError("unused") }
}
