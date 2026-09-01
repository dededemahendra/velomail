import Testing
import Foundation
import VeloCore
@testable import VeloUI

/// A writer that refuses everything, so a send can be driven past the cap.
private final class RefusingWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        throw AuthError.server(code: "500", description: "boom")
    }
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        throw AuthError.server(code: "500", description: "boom")
    }
}

@MainActor
@Suite struct FailureBannerTests {
    private func makeApp() throws -> (AppViewModel, OutboundService, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let outbound = OutboundService(writer: RefusingWriter(), store: store,
                                       mutations: mutations, identity: "me@x.com")
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store, outbound: outbound, identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, outbound, mutations)
    }

    /// Queues a send and drives it past the retry cap.
    private func failASend(_ outbound: OutboundService, _ mutations: MutationStore,
                           subject: String = "Lunch on Sunday") async throws {
        _ = try outbound.send(Draft(to: ["bob@x.com"], subject: subject, bodyText: "1pm?"),
                              after: 0)
        for _ in 0..<OutboundService.maxAttempts {
            try await outbound.drain()
            try mutations.retryFailed(maxAttempts: OutboundService.maxAttempts)
        }
    }

    @Test func nothingIsReportedWhenNothingHasFailed() throws {
        let (app, _, _) = try makeApp()
        #expect(app.failures.isEmpty)
        #expect(app.failurePrompt == nil)
    }

    @Test func aFailedSendIsReported() async throws {
        let (app, outbound, mutations) = try makeApp()
        try await failASend(outbound, mutations)

        app.refreshFailures()

        #expect(app.failurePrompt == "Not sent: Lunch on Sunday")
    }

    @Test func severalFailuresAreSteppedThroughOneAtATime() async throws {
        // Never in bulk: a single "dismiss all" over two failed sends would
        // throw away both drafts on one click.
        let (app, outbound, mutations) = try makeApp()
        try await failASend(outbound, mutations, subject: "One")
        try await failASend(outbound, mutations, subject: "Two")

        app.refreshFailures()

        #expect(app.failures.count == 2)
        #expect(app.failurePrompt == "Not sent: One")
        #expect(app.failureOverflow == 1)
    }

    @Test func dismissingTheFirstRevealsTheNext() async throws {
        let (app, outbound, mutations) = try makeApp()
        try await failASend(outbound, mutations, subject: "One")
        try await failASend(outbound, mutations, subject: "Two")
        app.refreshFailures()

        app.dismissFailure(try #require(app.failures.first))

        #expect(app.failurePrompt == "Not sent: Two")
        #expect(app.failureOverflow == 0)
    }

    @Test func reopeningPutsTheWordsBackInTheComposer() async throws {
        let (app, outbound, mutations) = try makeApp()
        try await failASend(outbound, mutations)
        app.refreshFailures()

        app.reopenFailure(try #require(app.failures.first))

        #expect(app.route == .compose)
        #expect(app.compose.subject == "Lunch on Sunday")
        #expect(app.compose.body == "1pm?")
        #expect(app.failures.isEmpty)
    }

    @Test func dismissingClearsIt() async throws {
        let (app, outbound, mutations) = try makeApp()
        try await failASend(outbound, mutations)
        app.refreshFailures()

        app.dismissFailure(try #require(app.failures.first))

        #expect(app.failures.isEmpty)
        #expect(app.failurePrompt == nil)
    }

    @Test func theBannerOutlastsTheUndoWindow() async throws {
        // Unlike undo, this is not a ten second offer: a message that never
        // went has to still be there when the writer next looks up.
        //
        // Driven rather than slept through. The old form waited 60ms against a
        // ten-second window, which proves almost nothing -- it would have
        // passed even if the banner expired at eleven seconds. Winding the
        // clock well past the undo window is the assertion that was meant.
        let (app, outbound, mutations) = try makeApp()
        let clock = TestClock()
        app.afterDelay = clock.delay
        try await failASend(outbound, mutations)

        app.refreshFailures()
        #expect(app.failurePrompt != nil)

        clock.advance(by: AppViewModel.undoWindow * 3)

        #expect(app.failurePrompt != nil)
    }
}
