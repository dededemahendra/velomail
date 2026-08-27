import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct SyncNowTests {
    private func makeApp(_ pass: (@Sendable () async throws -> Void)?) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, syncNow: pass)
        try app.start()
        return app
    }

    @Test func thereIsAWayToAskForASyncByHand() {
        // The loop backs off further after every failure. Without this the
        // only way to try again was to quit the app.
        #expect(CommandRegistry.v1.commands.map(\.title).contains("Sync now"))
    }

    @Test func theCommandIsWiredToSomething() async throws {
        // Five features in this app were built and left unreachable. This is
        // the check that would have caught them.
        let ran = Counter()
        let app = try makeApp { await ran.bump() }
        app.perform(.syncNow)
        try await Task.sleep(for: .milliseconds(120))
        #expect(await ran.count == 1)
    }

    @Test func aGoodPassSaysSo() async throws {
        let app = try makeApp { }
        await app.syncMailNow()
        #expect(app.notice == "Up to date")
    }

    @Test func aFailedPassConfirmsThePressWasHeard() async throws {
        // A failed pass can leave the list looking exactly as it did, so
        // silence would read as the keystroke having been dropped.
        let app = try makeApp { throw AuthError.invalidResponse }
        await app.syncMailNow()
        #expect(app.notice == "Could not reach Gmail")
    }

    @Test func withNoEngineBehindItNothingHappens() async throws {
        // Demo mode has no Gmail to reach.
        let app = try makeApp(nil)
        await app.syncMailNow()
        #expect(app.notice == nil)
    }
}

private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}

@MainActor
@Suite struct NoticeLifetimeTests {
    private func makeApp() throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, syncNow: { })
        try app.start()
        app.noticeWindow = 0.05
        return app
    }

    @Test func aPassingMessagePasses() async throws {
        // It had no lifetime at all: "Up to date" stayed until the reader
        // happened to sync again.
        let app = try makeApp()
        await app.syncMailNow()
        #expect(app.notice == "Up to date")
        try await Task.sleep(for: .milliseconds(200))
        #expect(app.notice == nil)
    }

    @Test func theSameMessageTwiceKeepsItsFullWindow() async throws {
        // Comparing by text alone would let the first countdown clear the
        // second message early.
        let app = try makeApp()
        app.noticeWindow = 0.35
        await app.syncMailNow()
        try await Task.sleep(for: .milliseconds(250))
        await app.syncMailNow()
        try await Task.sleep(for: .milliseconds(200))
        // The first timer has fired by now; the second must have survived it.
        #expect(app.notice == "Up to date")
    }
}
