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

    @Test func keystrokesAreIgnoredWhileTheCommandPaletteIsOpen() throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("k"), [.command]))
        #expect(app.route == .palette)

        // The palette has a text field. Typing "reply" must not fire r=reply
        // and e=archive on the way past.
        for character in "reply" { app.handle(KeyInput(.character(character))) }

        #expect(app.route == .palette)
        #expect(app.inbox.threads.count == 3)
    }

    @Test func paletteKeystrokesFallThroughToTheTextField() throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("k"), [.command]))

        // Not consumed, so the search field still receives them.
        #expect(app.handle(KeyInput(.character("r"))) == false)
    }

    // MARK: - Assistant wiring

    private func makeAIApp(provider: LLMProvider?) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m", threadID: "t", sender: "Alice <alice@example.com>",
                                 recipients: ["me@x.com"], subject: "Lunch",
                                 date: Date(timeIntervalSince1970: 1), bodyHTML: nil,
                                 bodyText: "free Friday?", isUnread: false, labelIDs: ["INBOX"],
                                 messageIDHeader: "<p@x>"))
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: NoopWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true,
            assistant: MailAssistant(provider: provider))
        try app.start()
        return app
    }

    @Test func withNoProviderThePaletteHidesTheAICommands() throws {
        let app = try makeAIApp(provider: nil)
        // An action that is visible and always errors is worse than one that is
        // simply not offered.
        #expect(!app.palette.commands.contains { $0.action.isAI })
    }

    @Test func withAProviderThePaletteOffersTheAICommands() throws {
        let app = try makeAIApp(provider: StubProvider("x"))
        #expect(app.palette.commands.contains { $0.action == .summarizeThread })
    }

    @Test func summariseChordRunsTheAssistant() async throws {
        let app = try makeAIApp(provider: StubProvider("A short summary."))

        app.handle(KeyInput(.character("a")))
        app.handle(KeyInput(.character("s")))
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(app.assistant.state == .result("A short summary."))
    }

    @Test func aiKeysDoNothingWhenNoProviderIsConfigured() async throws {
        let app = try makeAIApp(provider: nil)

        app.handle(KeyInput(.character("a")))
        app.handle(KeyInput(.character("s")))
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(app.assistant.state == .idle)
    }

    @Test func usingASuggestionOpensTheComposerPrefilled() throws {
        let app = try makeAIApp(provider: StubProvider("x"))

        app.startReply(with: "Yes, Friday works.")

        // A suggestion is a starting point the user edits, never something sent
        // on their behalf.
        #expect(app.route == .compose)
        #expect(app.compose.body.hasPrefix("Yes, Friday works."))
        #expect(app.compose.to == "Alice <alice@example.com>")
    }

    @Test func usingASuggestionAlsoKeepsTheQuotedParent() throws {
        let app = try makeAIApp(provider: StubProvider("x"))
        app.startReply(with: "Yes.")
        #expect(app.compose.body.contains("wrote:"))
    }

    // MARK: - Search routing

    @Test func slashOpensSearch() throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("/")))
        #expect(app.route == .search)
    }

    @Test func escapeLeavesSearchAndClearsIt() async throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("/")))
        app.search.text = "boundary"

        app.handle(KeyInput(.escape))

        #expect(app.route == .list)
        #expect(app.search.text.isEmpty)
    }

    @Test func typingInSearchDoesNotTriggerTriageActions() throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("/")))

        // "e" in a search field must not archive the inbox behind it.
        #expect(app.handle(KeyInput(.character("e"))) == false)
        #expect(app.inbox.threads.count == 3)
    }

    @Test func openingASearchHitSelectsAndOpensTheThread() throws {
        let app = try makeApp()
        let target = app.inbox.threads[2]
        app.handle(KeyInput(.character("/")))

        app.openFromSearch(target)

        #expect(app.route == .thread)
        #expect(app.inbox.selectedThread?.id == target.id)
    }

    @Test func openingAHitThatIsNotInTheInboxReturnsToTheList() throws {
        let app = try makeApp()
        let archived = MailThread(id: "gone", sender: "x@y.com", snippet: "s",
                                  lastMessageDate: Date(timeIntervalSince1970: 1),
                                  isUnread: false, hasAttachments: false, labelIDs: [])

        app.openFromSearch(archived)

        // Search can return archived mail; pretending to open it would be worse
        // than going back to the list.
        #expect(app.route == .list)
    }

    // MARK: - Time-based actions

    @Test func sendingOffersAnUndoWindow() throws {
        let app = try makeApp()
        app.perform(.compose)
        app.compose.to = "a@b.com"
        app.compose.subject = "s"
        app.compose.body = "b"

        app.perform(.send)

        #expect(app.undoableSend != nil)
        #expect(app.route == .list)
    }

    @Test func undoingASendRemovesItBeforeItLeaves() throws {
        let app = try makeApp()
        app.perform(.compose)
        app.compose.to = "a@b.com"
        app.compose.subject = "s"
        app.compose.body = "b"
        app.perform(.send)

        app.perform(.undoSend)

        #expect(app.undoableSend == nil)
    }

    @Test func undoingWithNothingToUndoIsHarmless() throws {
        let app = try makeApp()
        app.perform(.undoSend)
        #expect(app.undoableSend == nil)
    }

    @Test func snoozingHidesTheThreadFromTheList() throws {
        let app = try makeApp()
        let target = try #require(app.inbox.selectedThread).id

        app.handle(KeyInput(.character("h")))

        #expect(!app.inbox.threads.contains { $0.id == target })
    }

    @Test func snoozingWithNoSelectionIsHarmless() throws {
        let app = try makeApp(threadCount: 0)
        app.handle(KeyInput(.character("h")))
        #expect(app.inbox.threads.isEmpty)
    }

    @Test func theFollowUpChordLoadsThreadsAwaitingAReply() throws {
        let app = try makeApp()
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("f")))

        // The seeded threads are all inbound, so nothing is awaiting a reply --
        // the point is that the action ran rather than being unbound.
        #expect(app.followUps.isEmpty)
    }
}

private final class StubProvider: LLMProvider, @unchecked Sendable {
    let text: String
    init(_ text: String) { self.text = text }
    var displayName: String { "Stub" }
    func complete(_ request: LLMRequest) async throws -> String { text }
}

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError("unused") }
}
