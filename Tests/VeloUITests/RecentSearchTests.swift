import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct RecentSearchTests {
    private func makeModel(_ defaults: UserDefaults) throws -> SearchViewModel {
        let db = try AppDatabase.makeInMemory()
        return SearchViewModel(search: SearchService(db),
                               translator: QueryTranslator(assistant: MailAssistant(provider: nil)),
                               preferences: AppPreferences(defaults: defaults))
    }

    @Test func whatYouSearchedForIsRemembered() async throws {
        // Typing the same query from memory is the commonest thing anyone does
        // in a search field, and the app asked for it every time.
        let model = try makeModel(scratchDefaults())
        model.text = "invoice somerville"
        await model.run()
        #expect(model.recents == ["invoice somerville"])
    }

    @Test func aSearchThatFoundNothingIsStillRemembered() async throws {
        // That is the one you are most likely to want to edit and try again.
        let model = try makeModel(scratchDefaults())
        model.text = "nothing matches this"
        await model.run()
        #expect(model.recents.contains("nothing matches this"))
    }

    @Test func anEmptyQueryIsNotAHistoryEntry() async throws {
        let model = try makeModel(scratchDefaults())
        model.text = "   "
        await model.run()
        #expect(model.recents.isEmpty)
    }

    @Test func theSameSearchTwiceIsOneEntry() async throws {
        let model = try makeModel(scratchDefaults())
        for _ in 0..<3 { model.text = "peta"; await model.run() }
        #expect(model.recents == ["peta"])
    }

    @Test func itSurvivesQuitting() async throws {
        let defaults = scratchDefaults()
        let first = try makeModel(defaults)
        first.text = "wellington dam"
        await first.run()

        let second = try makeModel(defaults)
        #expect(second.recents == ["wellington dam"])
    }

    @Test func theListStaysShortEnoughToRead() async throws {
        let model = try makeModel(scratchDefaults())
        for i in 0..<9 { model.text = "query \(i)"; await model.run() }
        #expect(model.recents.count == SearchViewModel.recentLimit)
        #expect(model.recents.first == "query 8")
    }

    @Test func runningOneAgainPutsItBackInTheField() async throws {
        let model = try makeModel(scratchDefaults())
        await model.rerun("invoice")
        #expect(model.text == "invoice")
        #expect(model.recents.first == "invoice")
    }
}
