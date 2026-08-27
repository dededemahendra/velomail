import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct SendLaterTests {
    private func makeApp() throws -> (AppViewModel, OutboundService) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let outbound = OutboundService(writer: Quiet(), store: store,
                                       mutations: MutationStore(db), identity: "me@x.com")
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store, outbound: outbound, identity: "me@x.com", isSignedIn: true,
            drafts: DraftStore(db))
        try app.start()
        return (app, outbound)
    }

    private func write(_ app: AppViewModel, subject: String = "Tomorrow's note") {
        app.compose.startNew()
        app.compose.to = "bob@x.com"
        app.compose.subject = subject
        app.compose.body = "b"
    }

    // MARK: - Scheduling

    @Test func aMessageCanBeSentTomorrow() throws {
        let (app, outbound) = try makeApp()
        write(app)

        app.sendLater(Horizon.tomorrow())

        let waiting = try outbound.scheduled()
        #expect(waiting.map(\.draft.subject) == ["Tomorrow's note"])
        #expect(waiting.first!.dueAt > Date().addingTimeInterval(3_600))
    }

    @Test func schedulingClearsTheComposer() throws {
        // The message is finished and gone from your hands; leaving it on
        // screen invites sending it twice.
        let (app, _) = try makeApp()
        write(app)

        app.sendLater(Horizon.tomorrow())

        #expect(app.compose.subject.isEmpty)
        #expect(app.route == .list)
    }

    @Test func anUnsendableMessageIsNotScheduled() throws {
        let (app, outbound) = try makeApp()
        app.compose.startNew()          // no recipient

        app.sendLater(Horizon.tomorrow())

        #expect(try outbound.scheduled().isEmpty)
    }

    @Test func schedulingLeavesNoDraftBehind() throws {
        let (app, outbound) = try makeApp()
        write(app)
        app.compose.autosave()

        app.sendLater(Horizon.tomorrow())

        #expect(app.compose.storedDrafts.isEmpty)
        #expect(try outbound.scheduled().count == 1)
    }

    // MARK: - Seeing and changing it

    @Test func scheduledSendsShowOnTheDraftsScreen() throws {
        // Both are messages not yet gone; two screens for that would be one too
        // many, and `g d` is where a writer looks for unfinished business.
        let (app, _) = try makeApp()
        write(app)
        app.sendLater(Horizon.tomorrow())

        app.perform(.goToDrafts)

        #expect(app.scheduled.map(\.draft.subject) == ["Tomorrow's note"])
    }

    @Test func oneCanBeSentImmediately() throws {
        let (app, outbound) = try makeApp()
        write(app)
        app.sendLater(Horizon.tomorrow())
        app.perform(.goToDrafts)

        app.sendNow(try #require(app.scheduled.first))

        #expect(app.scheduled.isEmpty)
        #expect(try outbound.scheduled().isEmpty)
    }

    @Test func unschedulingPutsTheWordsBackInTheComposer() throws {
        let (app, _) = try makeApp()
        write(app, subject: "Second thoughts")
        app.sendLater(Horizon.tomorrow())
        app.perform(.goToDrafts)

        app.unschedule(try #require(app.scheduled.first))

        #expect(app.route == .compose)
        #expect(app.compose.subject == "Second thoughts")
        #expect(app.scheduled.isEmpty)
    }

    @Test func sendLaterIsInTheCommandPalette() throws {
        let titles = CommandRegistry.v1.commands.map(\.title)
        #expect(titles.contains { $0.lowercased().contains("send tomorrow") })
        #expect(titles.contains { $0.lowercased().contains("send next week") })
    }
}
