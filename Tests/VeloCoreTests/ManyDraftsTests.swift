import Testing
import Foundation
@testable import VeloCore

@Suite struct ManyDraftsTests {
    private func makeStore() throws -> DraftStore { DraftStore(try AppDatabase.makeInMemory()) }

    private func draft(_ subject: String) -> Draft {
        Draft(to: ["someone@x.com"], subject: subject, bodyText: "b")
    }

    private let t0 = Date(timeIntervalSince1970: 1_000)

    // MARK: - Keeping more than one

    @Test func twoDraftsBothSurvive() throws {
        // The whole point: starting a second message must not destroy the first.
        let store = try makeStore()
        try store.save(draft("To Alice"), id: "a", at: t0)
        try store.save(draft("To Bob"), id: "b", at: t0.addingTimeInterval(60))

        #expect(try store.all().map(\.draft.subject).sorted() == ["To Alice", "To Bob"])
    }

    @Test func savingAgainUpdatesRatherThanAccumulates() throws {
        let store = try makeStore()
        try store.save(draft("First words"), id: "a", at: t0)
        try store.save(draft("Second thoughts"), id: "a", at: t0.addingTimeInterval(60))

        #expect(try store.all().map(\.draft.subject) == ["Second thoughts"])
    }

    @Test func theMostRecentlyTouchedComesFirst() throws {
        let store = try makeStore()
        try store.save(draft("Older"), id: "a", at: t0)
        try store.save(draft("Newer"), id: "b", at: t0.addingTimeInterval(60))

        #expect(try store.all().map(\.draft.subject) == ["Newer", "Older"])
    }

    // MARK: - Reaching one

    @Test func aDraftCanBeLoadedByItsOwnID() throws {
        let store = try makeStore()
        try store.save(draft("To Alice"), id: "a", at: t0)
        try store.save(draft("To Bob"), id: "b", at: t0)

        #expect(try store.load(id: "a")?.draft.subject == "To Alice")
    }

    @Test func loadingWithNoIDTakesTheMostRecent() throws {
        // What "resume what I was writing" means with more than one in flight.
        let store = try makeStore()
        try store.save(draft("Older"), id: "a", at: t0)
        try store.save(draft("Newer"), id: "b", at: t0.addingTimeInterval(60))

        #expect(try store.latest()?.draft.subject == "Newer")
    }

    @Test func aStoredDraftKnowsItsOwnID() throws {
        // Without this the composer cannot tell which row to update.
        let store = try makeStore()
        try store.save(draft("To Alice"), id: "a", at: t0)

        #expect(try store.latest()?.id == "a")
    }

    // MARK: - Discarding

    @Test func discardingOneLeavesTheOthers() throws {
        let store = try makeStore()
        try store.save(draft("To Alice"), id: "a", at: t0)
        try store.save(draft("To Bob"), id: "b", at: t0)

        try store.discard(id: "a")

        #expect(try store.all().map(\.draft.subject) == ["To Bob"])
    }

    @Test func discardingSomethingUnknownIsHarmless() throws {
        let store = try makeStore()
        try store.save(draft("To Alice"), id: "a", at: t0)

        try store.discard(id: "nope")

        #expect(try store.all().count == 1)
    }

    @Test func anEmptyStoreHasNothingToResume() throws {
        #expect(try makeStore().latest() == nil)
        #expect(try makeStore().all().isEmpty)
    }
}
