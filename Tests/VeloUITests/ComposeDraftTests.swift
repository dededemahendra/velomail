import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct ComposeDraftTests {
    private func makeContext() throws -> (ComposeViewModel, DraftStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let drafts = DraftStore(db)
        let outbound = OutboundService(writer: SilentWriter(), store: store,
                                       mutations: MutationStore(db), identity: "me@example.com")
        return (ComposeViewModel(outbound: outbound, identity: "me@example.com", drafts: drafts), drafts)
    }

    @Test func anUntouchedComposerSavesNothing() throws {
        let (model, drafts) = try makeContext()
        model.startNew()

        model.autosave()

        // Otherwise pressing compose, then Escape, leaves a phantom draft to
        // resume forever.
        #expect(try drafts.latest() == nil)
    }

    @Test func typingARecipientIsEnoughToSave() throws {
        let (model, drafts) = try makeContext()
        model.startNew()
        model.to = "a@b.com"

        model.autosave()

        #expect(try drafts.latest()?.draft.to == ["a@b.com"])
    }

    @Test func typingABodyIsEnoughToSave() throws {
        let (model, drafts) = try makeContext()
        model.startNew()
        model.body = "I was saying"

        model.autosave()

        #expect(try drafts.latest()?.draft.bodyText.contains("I was saying") == true)
    }

    @Test func aSignatureAloneIsNotADraft() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let drafts = DraftStore(db)
        let model = ComposeViewModel(
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@example.com"),
            identity: "me@example.com",
            library: SnippetLibrary(signature: "-- \nWarren", snippets: []),
            drafts: drafts)
        model.startNew()

        model.autosave()

        // The signature was put there by the app, not typed by the user.
        #expect(try drafts.latest() == nil)
    }

    @Test func resumingRestoresEveryField() throws {
        let (model, _) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        model.subject = "Half written"
        model.body = "I was saying"
        model.autosave()

        model.startNew()          // wipe the in-memory state
        #expect(model.to.isEmpty)
        model.resumeDraft()

        #expect(model.to == "a@b.com")
        #expect(model.subject == "Half written")
        #expect(model.body == "I was saying")
    }

    @Test func resumingWithNothingStoredLeavesAFreshComposer() throws {
        let (model, _) = try makeContext()
        model.startNew()

        model.resumeDraft()

        #expect(model.to.isEmpty)
    }

    @Test func aResumedReplyStaysAReply() throws {
        let (model, _) = try makeContext()
        let parent = Message(id: "m", threadID: "t", sender: "Alice <alice@example.com>",
                             recipients: ["me@example.com"], subject: "Lunch",
                             date: Date(timeIntervalSince1970: 1), bodyHTML: nil,
                             bodyText: "free?", isUnread: false, labelIDs: [],
                             messageIDHeader: "<p@x.com>")
        model.startReply(to: parent)
        model.body = "Yes" + model.body
        model.autosave()

        model.startNew()
        model.resumeDraft()

        // Losing the thread would turn a resumed reply into a new message.
        #expect(model.isReply)
        #expect(model.to == "Alice <alice@example.com>")
        #expect(model.subject == "Re: Lunch")
    }

    @Test func sendingClearsTheDraft() throws {
        let (model, drafts) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        model.body = "done"
        model.autosave()

        try model.send()

        #expect(try drafts.latest() == nil)
    }

    @Test func discardingClearsTheDraftAndTheComposer() throws {
        let (model, drafts) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        model.autosave()

        model.discardDraft()

        #expect(try drafts.latest() == nil)
        #expect(model.to.isEmpty)
    }

    @Test func thereIsADraftToResumeOnlyWhenOneWasSaved() throws {
        let (model, _) = try makeContext()
        #expect(!model.hasStoredDraft)

        model.startNew()
        model.to = "a@b.com"
        model.autosave()

        #expect(model.hasStoredDraft)
    }

    @Test func attachmentsComeBackWithAResumedDraft() throws {
        let (model, _) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("invoice.pdf")
        try Data("PDF".utf8).write(to: file)
        try model.attach(file)
        model.autosave()

        model.startNew()
        model.resumeDraft()

        #expect(model.attachments.map(\.filename) == ["invoice.pdf"])
    }

    // MARK: - Through the app

    private func makeApp() throws -> (AppViewModel, DraftStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let drafts = DraftStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, drafts: drafts)
        try app.start()
        return (app, drafts)
    }

    @Test func composingResumesAStoredDraftRatherThanStartingBlank() throws {
        let (app, drafts) = try makeApp()
        try drafts.save(Draft(to: ["a@b.com"], subject: "Half written",
                              bodyText: "I was saying"), id: "seed")

        app.handle(KeyInput(.character("c")))

        // A blank window here would silently discard their work.
        #expect(app.route == .compose)
        #expect(app.compose.subject == "Half written")
    }

    @Test func composingWithNoDraftGivesAFreshWindow() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("c")))

        #expect(app.route == .compose)
        #expect(app.compose.subject.isEmpty)
    }

    @Test func discardFromThePaletteClearsWhatIsOnScreen() throws {
        // Discard acts on the message in the composer, not on whatever happens
        // to be the newest row: with several drafts in flight, a palette
        // command that binned an unrelated one would be the old bug wearing a
        // different hat.
        let (app, drafts) = try makeApp()
        try drafts.save(Draft(to: ["a@b.com"], subject: "Half written", bodyText: "x"), id: "seed")

        app.handle(KeyInput(.character("c")))   // resumes it
        app.perform(.discardDraft)

        #expect(try drafts.latest() == nil)
    }
}
