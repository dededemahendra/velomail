import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct ComposeIdentityTests {
    private func makeApp(as identity: String) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: identity),
            identity: identity, isSignedIn: true)
        try app.start()
        return app
    }

    @Test func theWindowSaysWhichAccountItGoesOutAs() throws {
        // With more than one account signed in there was nothing on screen
        // saying which one you were writing from.
        let app = try makeApp(as: "warren@livinglegacyforest.com")
        #expect(app.compose.sendingAs == "warren@livinglegacyforest.com")
    }

    @Test func theOfferSaysHowLongItLasts() throws {
        // Ten seconds with no sign of how many are left makes a deliberate
        // wait feel like a gamble.
        let app = try makeApp(as: "me@x.com")
        app.perform(.compose)
        app.compose.to = "a@b.com"
        app.compose.subject = "Hi"
        app.compose.body = "hi"
        app.perform(.send)

        let deadline = try #require(app.undoDeadline)
        #expect(deadline > Date())
        #expect(deadline <= Date().addingTimeInterval(AppViewModel.undoWindow + 1))
    }

    @Test func theDeadlineGoesWhenTheOfferDoes() throws {
        let app = try makeApp(as: "me@x.com")
        app.handle(KeyInput(.character("e")))
        app.undo()
        #expect(app.undoDeadline == nil)
    }
}
