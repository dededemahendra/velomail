import Testing
import Foundation
import VeloCore
@testable import VeloUI

private final class StubProvider: LLMProvider, @unchecked Sendable {
    let text: String
    init(_ text: String) { self.text = text }
    var displayName: String { "Stub" }
    func complete(_ request: LLMRequest) async throws -> String { text }
}

@MainActor
@Suite struct SearchViewModelTests {
    private func makeModel(provider: LLMProvider? = nil) throws -> (SearchViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for (index, body) in ["the eastern boundary", "budget approval", "boundary again"].enumerated() {
            let id = "t\(index)"
            let date = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 - index * 86_400))
            try store.upsert(MailThread(id: id, sender: "Salsa <salsa@example.com>", snippet: body,
                                        lastMessageDate: date, isUnread: false,
                                        hasAttachments: false, labelIDs: ["INBOX"]))
            try store.upsert(Message(id: "m\(index)", threadID: id, sender: "Salsa <salsa@example.com>",
                                     recipients: [], subject: "Plot map", date: date,
                                     bodyHTML: nil, bodyText: body, isUnread: false,
                                     labelIDs: ["INBOX"]))
        }
        let model = SearchViewModel(
            search: SearchService(db),
            translator: QueryTranslator(assistant: MailAssistant(provider: provider)))
        return (model, store)
    }

    @Test func startsEmpty() throws {
        let (model, _) = try makeModel()
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
    }

    @Test func aPlainQueryFindsThreads() async throws {
        let (model, _) = try makeModel()

        model.text = "boundary"
        await model.run()

        #expect(model.results.map(\.id) == ["t0", "t2"])
    }

    @Test func clearingTheQueryClearsTheResults() async throws {
        let (model, _) = try makeModel()
        model.text = "boundary"
        await model.run()

        model.text = ""
        await model.run()

        #expect(model.results.isEmpty)
    }

    @Test func noMatchesLeavesAnEmptyResultNotAnError() async throws {
        let (model, _) = try makeModel()

        model.text = "zebra"
        await model.run()

        #expect(model.results.isEmpty)
        #expect(model.failure == nil)
    }

    @Test func naturalLanguageIsTranslatedBeforeSearching() async throws {
        // The model narrows to "budget"; without translation "show me the budget
        // thread" would match nothing.
        let (model, _) = try makeModel(provider: StubProvider(#"{"terms":"budget"}"#))

        model.text = "show me the budget thread"
        await model.run()

        #expect(model.results.map(\.id) == ["t1"])
    }

    @Test func withNoModelTheRawTextIsStillSearched() async throws {
        let (model, _) = try makeModel()

        model.text = "budget"
        await model.run()

        #expect(model.results.map(\.id) == ["t1"])
    }

    @Test func selectionFollowsTheResults() async throws {
        let (model, _) = try makeModel()

        model.text = "boundary"
        await model.run()

        #expect(model.selected?.id == "t0")
        model.moveDown()
        #expect(model.selected?.id == "t2")
        model.moveDown()
        #expect(model.selected?.id == "t2")     // stops at the end
    }

    @Test func selectionResetsWhenResultsChange() async throws {
        let (model, _) = try makeModel()
        model.text = "boundary"
        await model.run()
        model.moveDown()

        model.text = "budget"
        await model.run()

        #expect(model.selected?.id == "t1")
    }

    @Test func clearResetsEverything() async throws {
        let (model, _) = try makeModel()
        model.text = "boundary"
        await model.run()

        model.clear()

        #expect(model.text.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.selected == nil)
    }
}
