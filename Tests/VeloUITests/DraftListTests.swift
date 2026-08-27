import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct DraftListTests {
    private func makeApp() throws -> (AppViewModel, DraftStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let drafts = DraftStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, drafts: drafts)
        try app.start()
        return (app, drafts)
    }

    private func seed(_ drafts: DraftStore) throws {
        try drafts.save(Draft(to: ["alice@x.com"], subject: "To Alice", bodyText: "a"),
                        id: "a", at: Date(timeIntervalSince1970: 100))
        try drafts.save(Draft(to: ["bob@x.com"], subject: "To Bob", bodyText: "b"),
                        id: "b", at: Date(timeIntervalSince1970: 200))
    }

    // MARK: - Getting there

    @Test func gDOpensTheDraftList() throws {
        let (app, drafts) = try makeApp()
        try seed(drafts)

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("d")))

        #expect(app.route == .drafts)
        #expect(app.drafts.map(\.draft.subject) == ["To Bob", "To Alice"])
    }

    @Test func focusModeMovedToGZ() throws {
        // `g d` is drafts everywhere else in mail; focus mode is ours to place.
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("z")))
        #expect(app.isFocused)
    }

    @Test func theListIsAlwaysFreshWhenOpened() throws {
        // A draft written since the last visit has to be in it.
        let (app, drafts) = try makeApp()
        app.perform(.goToDrafts)
        #expect(app.drafts.isEmpty)

        try seed(drafts)
        app.perform(.goToDrafts)

        #expect(app.drafts.count == 2)
    }

    // MARK: - Using it

    @Test func choosingOneResumesItInTheComposer() throws {
        let (app, drafts) = try makeApp()
        try seed(drafts)
        app.perform(.goToDrafts)

        app.resumeDraft(try #require(app.drafts.last))   // the older one

        #expect(app.route == .compose)
        #expect(app.compose.subject == "To Alice")
    }

    @Test func aResumedDraftKeepsItsRowRatherThanForking() throws {
        let (app, drafts) = try makeApp()
        try seed(drafts)
        app.perform(.goToDrafts)

        app.resumeDraft(try #require(app.drafts.last))
        app.compose.subject = "To Alice, finished"
        app.compose.autosave()

        #expect(try drafts.all().count == 2)
        #expect(try drafts.load(id: "a")?.draft.subject == "To Alice, finished")
    }

    @Test func discardingFromTheListRemovesOnlyThatOne() throws {
        let (app, drafts) = try makeApp()
        try seed(drafts)
        app.perform(.goToDrafts)

        app.discardDraft(try #require(app.drafts.first))

        #expect(app.drafts.map(\.draft.subject) == ["To Alice"])
        #expect(try drafts.all().count == 1)
    }

    @Test func backLeavesTheList() throws {
        let (app, drafts) = try makeApp()
        try seed(drafts)
        app.perform(.goToDrafts)

        app.perform(.back)

        #expect(app.route == .list)
    }

    @Test func draftsAreInTheCommandPalette() throws {
        let titles = CommandRegistry.v1.commands.map(\.title)
        #expect(titles.contains("Go to Drafts"))
    }

    @Test func theHeaderCountsEverythingOnScreen() throws {
        // Drafts and scheduled sends are both rows in this list, so a count
        // that ignored half of them would read as a bug.
        let drafts = [StoredDraft(id: "a", draft: Draft(to: [], subject: "d", bodyText: ""),
                                  updatedAt: Date())]
        let scheduled = [ScheduledSend(id: 1, draft: Draft(to: [], subject: "s", bodyText: ""),
                                       dueAt: Date().addingTimeInterval(90_000))]
        let view = DraftListView(drafts: drafts, scheduled: scheduled,
                                 onOpen: { _ in }, onDiscard: { _ in }, onClose: {})

        #expect(view.headerCount == 2)
    }
}
