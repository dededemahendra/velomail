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
    private func makeApp() throws -> (AppViewModel, TestClock) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, syncNow: { })
        try app.start()
        app.noticeWindow = 4
        // The countdown is driven rather than waited out. These used to set a
        // 50ms window and sleep 200ms, which is a race between two real timers
        // -- and one parallel run in three lost it.
        let clock = TestClock()
        app.afterDelay = clock.delay
        return (app, clock)
    }

    @Test func aPassingMessagePasses() async throws {
        // It had no lifetime at all: "Up to date" stayed until the reader
        // happened to sync again.
        let (app, clock) = try makeApp()
        await app.syncMailNow()
        #expect(app.notice == "Up to date")

        clock.advance(by: 3.9)
        #expect(app.notice == "Up to date", "cleared before its window was up")

        clock.advance(by: 0.2)
        #expect(app.notice == nil)
    }

    @Test func theSameMessageTwiceKeepsItsFullWindow() async throws {
        // Comparing by text alone would let the first countdown clear the
        // second message early.
        let (app, clock) = try makeApp()
        await app.syncMailNow()
        clock.advance(by: 3)
        await app.syncMailNow()

        // Past the first timer, well inside the second.
        clock.advance(by: 1.5)
        #expect(app.notice == "Up to date")

        // And the second still ends on time rather than living forever.
        clock.advance(by: 2.6)
        #expect(app.notice == nil)
    }
}

@MainActor
@Suite struct BrokenAddressTests {
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
        return app
    }

    @Test func aTypoStopsTheSendRatherThanFailingLater() throws {
        let app = try makeApp()
        app.perform(.compose)
        app.compose.to = "petaexample.com"
        app.compose.subject = "Hello"
        app.compose.body = "hi"

        app.perform(.send)

        #expect(app.sendWarning == .malformedAddress("petaexample.com"))
        #expect(app.undoPrompt == nil)   // nothing went
    }

    @Test func backingOutLeavesTheDraftThereToFix() throws {
        // The whole point: catching it late meant the message was gone and the
        // failure arrived as a line in a queue. Catching it here is only
        // useful if what you typed is still in front of you.
        let app = try makeApp()
        app.perform(.compose)
        app.compose.to = "petaexample.com"
        app.compose.subject = "Revised invoice"
        app.compose.body = "The planting moved to the 14th."
        app.perform(.send)

        app.cancelSend()

        #expect(app.route == .compose)
        #expect(app.compose.to == "petaexample.com")
        #expect(app.compose.subject == "Revised invoice")
        #expect(app.compose.body == "The planting moved to the 14th.")
    }

    @Test func aGoodAddressIsNotQuestioned() throws {
        let app = try makeApp()
        app.perform(.compose)
        app.compose.to = "peta@example.com"
        app.compose.subject = "Hello"
        app.compose.body = "hi"

        app.perform(.send)

        #expect(app.sendWarning == nil)
        #expect(app.undoPrompt == "Message sent")
    }
}
