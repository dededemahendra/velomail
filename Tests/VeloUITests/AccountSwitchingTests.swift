import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct AccountSwitchingTests {
    private func makeApp() throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        app.accounts = [Account(id: "primary", address: "warren@example.com"),
                        Account(id: "second", address: "gede@example.com")]
        app.currentAccount = "primary"
        return app
    }

    @Test func theOtherAccountsAreOfferedByName() throws {
        let app = try makeApp()
        #expect(app.palette.commands.contains { $0.title == "Switch to gede@example.com" })
    }

    @Test func theOpenOneIsNotOffered() throws {
        // Switching to where you already are is not a command.
        let app = try makeApp()
        #expect(!app.palette.commands.contains { $0.title == "Switch to warren@example.com" })
    }

    @Test func anAccountThatHasNotSaidWhoItIsStillHasAName() throws {
        // The address comes from Gmail's profile, so a freshly added account
        // has none until it syncs. "Switch to " with nothing after it is worse
        // than saying it plainly.
        let app = try makeApp()
        app.accounts = [Account(id: "primary", address: "warren@example.com"),
                        Account(id: "fresh", address: nil)]
        #expect(app.palette.commands.contains { $0.title == "Switch to Not signed in" })
    }

    @Test func switchingAsksTheHostRatherThanDoingItItself() throws {
        // The view model has no idea how an account is assembled, and should
        // not learn.
        let app = try makeApp()
        var asked: String?
        app.onSwitchAccount = { asked = $0 }

        app.run(Command(title: "x", action: .switchAccount, argument: "second"))

        #expect(asked == "second")
    }

    @Test func addingIsAlwaysOffered() throws {
        let app = try makeApp()
        #expect(app.palette.commands.contains { $0.title == "Add another account" })
    }

    @Test func addingAsksTheHostToo() throws {
        let app = try makeApp()
        var asked = false
        app.onAddAccount = { asked = true }

        app.run(Command(title: "x", action: .addAccount))

        #expect(asked)
    }
}
