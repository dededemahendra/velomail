import Testing
import Foundation
@testable import VeloCore

private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    var response: String
    var error: LLMError?
    private(set) var requests: [LLMRequest] = []
    init(_ response: String = "{}", error: LLMError? = nil) {
        self.response = response; self.error = error
    }
    var displayName: String { "Scripted" }
    func complete(_ request: LLMRequest) async throws -> String {
        requests.append(request)
        if let error { throw error }
        return response
    }
}

private let today = Date(timeIntervalSince1970: 1_756_000_000)   // 2025-08-24

@Suite struct QueryTranslatorTests {
    private func translator(_ provider: LLMProvider?) -> QueryTranslator {
        QueryTranslator(assistant: MailAssistant(provider: provider), now: { today })
    }

    // MARK: - Happy path

    @Test func extractsTermsAndSender() async throws {
        let provider = ScriptedProvider(#"{"terms":"open day","from":"natalie"}"#)

        let query = await translator(provider).translate("emails from natalie about the open day")

        #expect(query.terms == "open day")
        #expect(query.from == "natalie")
    }

    @Test func extractsUnread() async throws {
        let provider = ScriptedProvider(#"{"terms":"","isUnread":true}"#)
        #expect(await translator(provider).translate("unread mail").isUnread == true)
    }

    @Test func extractsADateRange() async throws {
        let provider = ScriptedProvider(#"{"terms":"invoice","after":"2025-08-01"}"#)

        let query = await translator(provider).translate("invoices since August")

        #expect(query.terms == "invoice")
        #expect(query.after != nil)
    }

    // MARK: - What models actually return

    @Test func jsonWrappedInCodeFencesIsParsed() async throws {
        let provider = ScriptedProvider("```json\n{\"terms\":\"budget\"}\n```")
        #expect(await translator(provider).translate("budget mail").terms == "budget")
    }

    @Test func jsonSurroundedByProseIsParsed() async throws {
        let provider = ScriptedProvider("Sure! Here is the query:\n{\"terms\":\"budget\"}\nHope that helps.")
        #expect(await translator(provider).translate("budget mail").terms == "budget")
    }

    @Test func nestedBracesDoNotConfuseExtraction() async throws {
        let provider = ScriptedProvider(#"prefix {"terms":"a","extra":{"nested":1}} suffix"#)
        #expect(await translator(provider).translate("x").terms == "a")
    }

    // MARK: - Degrading

    @Test func unparseableOutputFallsBackToTheRawText() async throws {
        let provider = ScriptedProvider("I am not going to answer that")

        let query = await translator(provider).translate("boundary map")

        // Which is exactly what a plain search box would have done anyway.
        #expect(query.terms == "boundary map")
    }

    @Test func aProviderFailureFallsBackToTheRawText() async throws {
        let provider = ScriptedProvider(error: .unavailable)
        #expect(await translator(provider).translate("boundary map").terms == "boundary map")
    }

    @Test func withNoProviderTheRawTextIsUsed() async throws {
        #expect(await translator(nil).translate("boundary map").terms == "boundary map")
    }

    @Test func anEmptyQueryStaysEmptyWithoutCallingTheModel() async throws {
        let provider = ScriptedProvider(#"{"terms":"x"}"#)

        let query = await translator(provider).translate("   ")

        #expect(query.isEmpty)
        #expect(provider.requests.isEmpty)      // no spend on an empty box
    }

    // MARK: - Privacy

    @Test func onlyTheQueryIsSentNeverMailContent() async throws {
        let provider = ScriptedProvider(#"{"terms":"x"}"#)

        _ = await translator(provider).translate("find the plot map thread")

        // The model translates; it never sees the mailbox.
        let prompt = try #require(provider.requests.first).prompt
        #expect(prompt.contains("find the plot map thread"))
        #expect(!prompt.lowercased().contains("from:"))     // no transcript headers
    }

    @Test func todaysDateIsSuppliedSoRelativeRangesCanResolve() async throws {
        let provider = ScriptedProvider(#"{"terms":"x"}"#)

        _ = await translator(provider).translate("last week")

        // The model has no clock.
        #expect(try #require(provider.requests.first).prompt.contains("2025-08-24"))
    }
}
