import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct SendConfirmationTests {
    private func makeApp() throws -> (AppViewModel, MutationStore, AppPreferences) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let suite = "velo.send.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPreferences(defaults: defaults)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: mutations, identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, preferences: preferences)
        try app.start()
        return (app, mutations, preferences)
    }

    private func write(_ app: AppViewModel, body: String, to: String = "bob@x.com") {
        app.compose.startNew()
        app.compose.to = to
        app.compose.subject = "Paperwork"
        app.compose.body = body
    }

    // MARK: - Being asked

    @Test func aMissingAttachmentStopsTheSendAndAsks() throws {
        let (app, mutations, _) = try makeApp()
        write(app, body: "See the attached plan.")

        app.perform(.send)

        #expect(app.sendWarning == .missingAttachment)
        #expect(try mutations.all().isEmpty)      // nothing has gone
    }

    @Test func confirmingSendsIt() throws {
        let (app, mutations, _) = try makeApp()
        write(app, body: "See the attached plan.")
        app.perform(.send)

        app.confirmSend()

        #expect(app.sendWarning == nil)
        #expect(try mutations.all().count == 1)
    }

    @Test func cancellingLeavesTheMessageAloneToFix() throws {
        // The whole point: the writer goes back and attaches the file.
        let (app, mutations, _) = try makeApp()
        write(app, body: "See the attached plan.")
        app.perform(.send)

        app.cancelSend()

        #expect(app.sendWarning == nil)
        #expect(app.route == .compose)
        #expect(app.compose.body == "See the attached plan.")
        #expect(try mutations.all().isEmpty)
    }

    @Test func anOrdinaryMessageIsNotQuestioned() throws {
        let (app, mutations, _) = try makeApp()
        write(app, body: "One o'clock works.")

        app.perform(.send)

        #expect(app.sendWarning == nil)
        #expect(try mutations.all().count == 1)
    }

    @Test func theCheckCanBeTurnedOff() throws {
        let (app, mutations, preferences) = try makeApp()
        preferences.warnsAboutAttachments = false
        write(app, body: "See the attached plan.")

        app.perform(.send)

        #expect(app.sendWarning == nil)
        #expect(try mutations.all().count == 1)
    }

    @Test func aCrowdIsQuestionedOnlyOnceALimitIsSet() throws {
        let (app, mutations, preferences) = try makeApp()
        preferences.recipientLimit = 3
        write(app, body: "Notes", to: "a@x.com, b@x.com, c@x.com, d@x.com")

        app.perform(.send)

        #expect(app.sendWarning == .manyRecipients(4))
        #expect(try mutations.all().isEmpty)
    }

    // MARK: - Reply behaviour

    @Test func rRepliesToTheSenderByDefault() throws {
        let (app, _, _) = try makeApp()
        #expect(!app.preferences.repliesToEveryone)
    }

    @Test func rCanBeMadeToAnswerEveryone() throws {
        let (app, _, preferences) = try makeApp()
        preferences.repliesToEveryone = true
        #expect(app.preferences.repliesToEveryone)
    }
}
