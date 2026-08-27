import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct SearchLimitTests {
    private func makeModel(threads: Int) throws -> SearchViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<threads {
            try store.upsert(MailThread(id: "t\(i)", sender: "peta@example.com",
                                        snippet: "planting", lastMessageDate: Date(),
                                        isUnread: false, hasAttachments: false,
                                        labelIDs: ["INBOX"]))
            try store.upsert(Message(id: "m\(i)", threadID: "t\(i)", sender: "peta@example.com",
                                     recipients: ["me@x.com"], subject: "planting \(i)",
                                     date: Date(), bodyHTML: nil, bodyText: "planting",
                                     isUnread: false, labelIDs: ["INBOX"]))
        }
        return SearchViewModel(search: SearchService(db),
                               translator: QueryTranslator(assistant: MailAssistant(provider: nil)))
    }

    @Test func aSearchThatFitsSaysNothingAboutLimits() async throws {
        let model = try makeModel(threads: 5)
        model.text = "planting"
        await model.run()
        #expect(model.results.count == 5)
        #expect(!model.truncated)
    }

    @Test func exactlyTheLimitIsNotCalledTruncated() async throws {
        // Fetching one extra is what makes this exact rather than a guess
        // from a suspiciously round number.
        let model = try makeModel(threads: SearchViewModel.resultLimit)
        model.text = "planting"
        await model.run()
        #expect(model.results.count == SearchViewModel.resultLimit)
        #expect(!model.truncated)
    }

    @Test func moreThanTheLimitSaysSo() async throws {
        // It capped at two hundred and said nothing, so a search that found
        // five hundred looked like a search that found two hundred.
        let model = try makeModel(threads: SearchViewModel.resultLimit + 30)
        model.text = "planting"
        await model.run()
        #expect(model.results.count == SearchViewModel.resultLimit)
        #expect(model.truncated)
    }

    @Test func theExtraOneIsNeverDrawn() async throws {
        let model = try makeModel(threads: SearchViewModel.resultLimit + 1)
        model.text = "planting"
        await model.run()
        #expect(model.results.count == SearchViewModel.resultLimit)
    }

    @Test func clearingForgetsTheWarning() async throws {
        let model = try makeModel(threads: SearchViewModel.resultLimit + 5)
        model.text = "planting"
        await model.run()
        model.clear()
        #expect(!model.truncated)
    }
}
