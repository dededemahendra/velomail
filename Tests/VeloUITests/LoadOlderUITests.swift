import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct LoadOlderUITests {
    private func makeApp(loader: @escaping @Sendable (Int) async throws -> Int) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true,
            loadOlder: loader)
        try app.start()
        return app
    }

    @Test func loadingOlderSaysHowMuchArrived() async throws {
        let app = try makeApp { _ in 42 }

        await app.loadOlderMail()

        #expect(app.syncStatus == .idle)
        #expect(app.notice == "42 older messages")
    }

    @Test func oneMessageIsNotPluralised() async throws {
        let app = try makeApp { _ in 1 }
        await app.loadOlderMail()
        #expect(app.notice == "1 older message")
    }

    @Test func reachingTheEndSaysSoRatherThanNothing() async throws {
        // Silence after pressing a button reads as a broken button.
        let app = try makeApp { _ in 0 }
        await app.loadOlderMail()
        #expect(app.notice == "Nothing older to fetch")
    }

    @Test func aFailureIsReportedNotSwallowed() async throws {
        let app = try makeApp { _ in throw AuthError.invalidResponse }
        await app.loadOlderMail()
        #expect(app.notice?.contains("Could not") == true)
    }

    @Test func withNoAccountThereIsNothingToLoad() async throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()

        await app.loadOlderMail()

        #expect(app.notice == nil)
    }

    @Test func itIsInTheCommandPalette() throws {
        #expect(CommandRegistry.v1.commands.map(\.title).contains("Load older mail"))
    }
}
