import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct CompositionTests {
    @Test func demoModeAssemblesARunnableAppWithMail() throws {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil))
        try assembly.app.start()

        // The wiring the app actually launches with: seeded store → view model.
        #expect(assembly.app.route == .list)
        #expect(assembly.app.inbox.threads.count == 6)
        #expect(assembly.app.inbox.selectedThread != nil)
        #expect(!assembly.app.inbox.selectedMessages.isEmpty)
    }

    @Test func demoThreadsCarryASenderForTheListRow() throws {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil))
        try assembly.app.start()

        #expect(assembly.app.inbox.threads.allSatisfy { !$0.sender.isEmpty })
    }

    @Test func demoModeHasNoSyncBecauseItHasNoCredentials() throws {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil))
        #expect(assembly.sync == nil)
    }

    @Test func triageWorksEndToEndThroughTheAssembledApp() throws {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil))
        let app = assembly.app
        try app.start()
        let second = app.inbox.threads[1].id

        app.handle(KeyInput(.character("e")))     // archive + auto-advance

        #expect(app.inbox.threads.count == 5)
        #expect(app.inbox.selectedThread?.id == second)
    }

    @Test func composingAndSendingRoundTripsThroughTheAssembledApp() throws {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil))
        let app = assembly.app
        try app.start()

        app.handle(KeyInput(.character("c")))
        #expect(app.route == .compose)
        app.compose.to = "someone@example.com"
        app.compose.subject = "Hello"
        app.compose.body = "Hi there"
        app.perform(.send)

        // Optimistically applied: the sent thread is in the store immediately.
        #expect(app.route == .list)
        let sent = try assembly.store.inboxThreads().count
        #expect(sent == 6)                        // demo threads unchanged; a sent thread is not in INBOX
    }

    @Test func demoIsUsableEvenThoughItHasNoClientID() throws {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil))
        try assembly.app.start()

        // Demo exists to be looked at without credentials, so it must reach the
        // mail surface rather than the setup screen.
        #expect(!assembly.app.isConfigured)
        #expect(assembly.app.route == .list)
    }
}
