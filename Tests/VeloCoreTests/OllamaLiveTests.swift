import Testing
import Foundation
@testable import VeloCore

/// Exercises the real provider against a real local Ollama.
///
/// Opt-in via `VELOMAIL_LIVE_OLLAMA=1`, because the suite must stay offline and
/// deterministic by default. Everything else here is mock-driven; this exists to
/// prove the wire format is right against the actual daemon, which no mock can.
private let liveEnabled = ProcessInfo.processInfo.environment["VELOMAIL_LIVE_OLLAMA"] == "1"
private let liveModel = ProcessInfo.processInfo.environment["VELOMAIL_OLLAMA_MODEL"]
    ?? OllamaProvider.defaultModel

@Suite(.enabled(if: liveEnabled), .serialized) struct OllamaLiveTests {
    private func makeAssistant() -> MailAssistant {
        MailAssistant(provider: OllamaProvider(
            model: liveModel,
            httpClient: URLSessionHTTPClient(session: LLMConfig.makeHTTPClientSession())))
    }

    private var thread: [Message] {
        [
            Message(id: "c1", threadID: "t", sender: "Warren <warren@example.com>",
                    recipients: ["salsa@example.com"], subject: "Somerville plot map",
                    date: Date(timeIntervalSince1970: 1_000), bodyHTML: nil,
                    bodyText: "Can we get the Somerville plot map updated before the open day?",
                    isUnread: false, labelIDs: []),
            Message(id: "c2", threadID: "t", sender: "Salsa <salsa@example.com>",
                    recipients: ["warren@example.com"], subject: "Re: Somerville plot map",
                    date: Date(timeIntervalSince1970: 2_000), bodyHTML: nil,
                    bodyText: "Yes. I have the survey file and will redraw the eastern boundary today.",
                    isUnread: false, labelIDs: []),
        ]
    }

    @Test func summarisesARealThroughARealModel() async throws {
        let summary = try await makeAssistant().summarize(messages: thread)
        #expect(!summary.isEmpty)
        // Not asserting wording -- that is the model's business. Asserting the
        // round trip produced usable prose about the right subject.
        #expect(summary.count > 20)
        print("[live] summary: \(summary)")
    }

    @Test func suggestsRepliesThroughARealModel() async throws {
        let replies = try await makeAssistant().suggestReplies(to: thread)
        #expect(!replies.isEmpty)
        #expect(replies.allSatisfy { !$0.isEmpty })
        print("[live] replies: \(replies)")
    }

    @Test func triagesThroughARealModel() async throws {
        let priority = try await makeAssistant().triage(messages: thread)
        print("[live] priority: \(priority.rawValue)")
        #expect(MailPriority.allCases.contains(priority))
    }

    @Test func rewritesThroughARealModel() async throws {
        let rewritten = try await makeAssistant().rewrite("yo can u send that file", tone: .formal)
        #expect(!rewritten.isEmpty)
        print("[live] rewrite: \(rewritten)")
    }
}
