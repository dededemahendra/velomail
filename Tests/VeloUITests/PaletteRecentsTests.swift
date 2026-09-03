import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct PaletteRecentsTests {
    private func makeApp(_ defaults: UserDefaults) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true,
            preferences: AppPreferences(defaults: defaults))
        try app.start()
        return app
    }

    @Test func runningACommandRemembersIt() throws {
        let app = try makeApp(scratchDefaults())
        app.run(Command(title: "Analytics", action: .showAnalytics))
        #expect(app.recentCommands.first == .showAnalytics)
    }

    @Test func whatYouReachForSurvivesQuitting() throws {
        // Session-only would reset the shortcut every morning.
        let defaults = scratchDefaults()
        let first = try makeApp(defaults)
        first.run(Command(title: "Analytics", action: .showAnalytics))

        let second = try makeApp(defaults)
        #expect(second.recentCommands.first == .showAnalytics)
    }

    @Test func aCommandRemovedInALaterVersionDoesNotWipeTheRest() throws {
        let defaults = scratchDefaults()
        defaults.set(["notAnActionAnyMore", MailAction.reply.rawValue],
                     forKey: "velomail.recentCommands")
        let app = try makeApp(defaults)
        #expect(app.recentCommands == [.reply])
    }

    @Test func keystrokesDoNotFillItWithJAndK() throws {
        // Only the palette records: a keymap is already fast, and folding
        // keystrokes in would make Recent a list of navigation.
        let app = try makeApp(scratchDefaults())
        app.handle(KeyInput(.character("j")))
        app.handle(KeyInput(.character("k")))
        #expect(app.recentCommands.isEmpty)
    }

    @Test func theTopOfThePaletteIsWhatYouJustRan() throws {
        let app = try makeApp(scratchDefaults())
        app.run(Command(title: "Analytics", action: .showAnalytics))
        #expect(app.palette.matches("", recents: app.recentCommands).first?.action == .showAnalytics)
    }
}
