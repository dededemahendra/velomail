import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct DraftIdentityTests {
    private func makeModel(_ drafts: DraftStore, ids: [String] = ["d1", "d2", "d3"])
        -> ComposeViewModel {
        let db = try! AppDatabase.makeInMemory()
        let store = MailStore(db)
        var next = ids.makeIterator()
        return ComposeViewModel(
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", drafts: drafts,
            newDraftID: { next.next() ?? "spare" })
    }

    private func makeStore() throws -> DraftStore { DraftStore(try AppDatabase.makeInMemory()) }

    // MARK: - The bug this exists to fix

    @Test func startingASecondMessageKeepsTheFirst() throws {
        let drafts = try makeStore()
        let model = makeModel(drafts)

        model.startNew()
        model.subject = "Half-written to Alice"
        model.autosave()

        model.startNew()
        model.subject = "Quick note to Bob"
        model.autosave()

        #expect(try drafts.all().map(\.draft.subject).sorted()
                == ["Half-written to Alice", "Quick note to Bob"])
    }

    @Test func editingOneDraftDoesNotForkIt() throws {
        // Typing more into the same composer updates its row rather than
        // leaving a trail of half-sentences.
        let drafts = try makeStore()
        let model = makeModel(drafts)

        model.startNew()
        model.subject = "One"
        model.autosave()
        model.subject = "One, expanded"
        model.autosave()

        #expect(try drafts.all().count == 1)
    }

    // MARK: - Getting back to one

    @Test func resumingTakesTheMostRecent() throws {
        let drafts = try makeStore()
        let model = makeModel(drafts)
        model.startNew(); model.subject = "Older"; model.autosave()
        model.startNew(); model.subject = "Newer"; model.autosave()

        model.startNew()
        model.resumeDraft()

        #expect(model.subject == "Newer")
    }

    @Test func aNamedDraftCanBeResumed() throws {
        let drafts = try makeStore()
        let model = makeModel(drafts)
        model.startNew(); model.subject = "Older"; model.autosave()
        model.startNew(); model.subject = "Newer"; model.autosave()

        let older = try #require(try drafts.all().first { $0.draft.subject == "Older" })
        model.resume(older)

        #expect(model.subject == "Older")
    }

    @Test func editingAResumedDraftUpdatesThatOneNotACopy() throws {
        let drafts = try makeStore()
        let model = makeModel(drafts)
        model.startNew(); model.subject = "Older"; model.autosave()
        model.startNew(); model.subject = "Newer"; model.autosave()

        let older = try #require(try drafts.all().first { $0.draft.subject == "Older" })
        model.resume(older)
        model.subject = "Older, finished"
        model.autosave()

        #expect(try drafts.all().count == 2)
        #expect(try drafts.load(id: older.id)?.draft.subject == "Older, finished")
    }

    // MARK: - Clearing one

    @Test func sendingClearsOnlyTheOneSent() throws {
        let drafts = try makeStore()
        let model = makeModel(drafts)
        model.startNew(); model.subject = "Keep me"; model.autosave()
        model.startNew()
        model.to = "bob@x.com"; model.subject = "Send me"
        try model.send()

        #expect(try drafts.all().map(\.draft.subject) == ["Keep me"])
    }

    @Test func discardingClearsOnlyTheOneOnScreen() throws {
        let drafts = try makeStore()
        let model = makeModel(drafts)
        model.startNew(); model.subject = "Keep me"; model.autosave()
        model.startNew(); model.subject = "Bin me"; model.autosave()

        model.discardDraft()

        #expect(try drafts.all().map(\.draft.subject) == ["Keep me"])
    }

    @Test func anUntouchedComposerStoresNothing() throws {
        // Opening compose and closing it again should not leave an empty draft
        // sitting in the list.
        let drafts = try makeStore()
        let model = makeModel(drafts)
        model.startNew()
        model.autosave()

        #expect(try drafts.all().isEmpty)
    }
}
