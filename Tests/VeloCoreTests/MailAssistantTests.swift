import Testing
import Foundation
@testable import VeloCore

/// Returns scripted text and records what it was asked.
private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    var response: String
    var error: LLMError?
    private(set) var requests: [LLMRequest] = []

    init(_ response: String = "ok", error: LLMError? = nil) {
        self.response = response
        self.error = error
    }

    var displayName: String { "Scripted" }

    func complete(_ request: LLMRequest) async throws -> String {
        requests.append(request)
        if let error { throw error }
        return response
    }
}

private func msg(_ text: String = "are you free?", subject: String = "Lunch") -> Message {
    Message(id: "m", threadID: "t", sender: "Alice <alice@example.com>",
            recipients: ["me@example.com"], subject: subject,
            date: Date(timeIntervalSince1970: 0), bodyHTML: nil, bodyText: text,
            isUnread: false, labelIDs: [])
}

@Suite struct MailAssistantTests {
    // MARK: - Single-value cleanup

    @Test func summarizeReturnsTheText() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("They want lunch on Friday."))
        #expect(try await assistant.summarize(messages: [msg()]) == "They want lunch on Friday.")
    }

    @Test func surroundingWhitespaceIsTrimmed() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("\n\n  answer  \n"))
        #expect(try await assistant.summarize(messages: [msg()]) == "answer")
    }

    @Test func aWrappingPairOfQuotesIsStripped() async throws {
        // Models like to quote a subject line back at you.
        let assistant = MailAssistant(provider: ScriptedProvider("\"Plot map for the open day\""))
        #expect(try await assistant.subjectLine(body: "x") == "Plot map for the open day")
    }

    @Test func aPreambleIsStripped() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("Here is the rewritten text:\nSounds good."))
        #expect(try await assistant.rewrite("ok", tone: .formal) == "Sounds good.")
    }

    @Test func quotesInsideTheTextAreKept() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider(#"She said "yes" already"#))
        #expect(try await assistant.summarize(messages: [msg()]) == #"She said "yes" already"#)
    }

    // MARK: - List parsing

    @Test func suggestedRepliesAreSplitPerLine() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("Yes, Friday works.\nCan we do Monday?\nI am away."))
        #expect(try await assistant.suggestReplies(to: [msg()]) ==
                ["Yes, Friday works.", "Can we do Monday?", "I am away."])
    }

    @Test func bulletsAndNumberingAreStripped() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("- one\n* two\n1. three\n2) four"))
        #expect(try await assistant.suggestReplies(to: [msg()]) == ["one", "two", "three", "four"])
    }

    @Test func blankLinesAreDropped() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("one\n\n\ntwo\n"))
        #expect(try await assistant.suggestReplies(to: [msg()]) == ["one", "two"])
    }

    @Test func anEmptyResponseYieldsNoSuggestions() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("   "))
        #expect(try await assistant.suggestReplies(to: [msg()]).isEmpty)
    }

    // MARK: - Triage

    @Test func triageParsesTheVocabulary() async throws {
        for priority in MailPriority.allCases {
            let assistant = MailAssistant(provider: ScriptedProvider(priority.rawValue))
            #expect(try await assistant.triage(messages: [msg()]) == priority)
        }
    }

    @Test func triageIsLenientAboutFormatting() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider("  Urgent.\n"))
        #expect(try await assistant.triage(messages: [msg()]) == .urgent)
    }

    @Test func anUnrecognisedTriageAnswerIsNormalNotUrgent() async throws {
        // A mis-parse must never invent urgency.
        let assistant = MailAssistant(provider: ScriptedProvider("I would say quite important really"))
        #expect(try await assistant.triage(messages: [msg()]) == .normal)
    }

    // MARK: - Plumbing

    @Test func theInstructionReachesTheProvider() async throws {
        let provider = ScriptedProvider("drafted")
        let assistant = MailAssistant(provider: provider)

        _ = try await assistant.draftReply(to: [msg()], instruction: "decline politely")

        #expect(provider.requests.first?.prompt.contains("decline politely") == true)
    }

    @Test func providerErrorsPropagateUnchanged() async throws {
        let assistant = MailAssistant(provider: ScriptedProvider(error: .unavailable))

        await #expect(throws: LLMError.unavailable) {
            _ = try await assistant.summarize(messages: [msg()])
        }
    }

    @Test func noProviderMeansNotConfiguredRatherThanACrash() async throws {
        let assistant = MailAssistant(provider: nil)
        #expect(!assistant.isAvailable)

        await #expect(throws: LLMError.notConfigured) {
            _ = try await assistant.summarize(messages: [msg()])
        }
    }

    @Test func summarisingNothingDoesNotCallTheModel() async throws {
        let provider = ScriptedProvider("should not be used")
        let assistant = MailAssistant(provider: provider)

        let summary = try await assistant.summarize(messages: [])

        #expect(summary.isEmpty)
        #expect(provider.requests.isEmpty)      // no spend on an empty thread
    }

    @Test func translationAndGrammarRoundTripThroughTheProvider() async throws {
        let provider = ScriptedProvider("hasil")
        let assistant = MailAssistant(provider: provider)

        #expect(try await assistant.translate("result", to: "Indonesian") == "hasil")
        #expect(provider.requests.last?.prompt.contains("Indonesian") == true)
        #expect(try await assistant.fixGrammar("i has went") == "hasil")
    }
}
