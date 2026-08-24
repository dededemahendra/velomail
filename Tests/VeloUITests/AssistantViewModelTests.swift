import Testing
import Foundation
import VeloCore
@testable import VeloUI

private final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    var response: String
    var error: LLMError?
    init(_ response: String = "ok", error: LLMError? = nil) {
        self.response = response; self.error = error
    }
    var displayName: String { "Scripted (test-model)" }
    func complete(_ request: LLMRequest) async throws -> String {
        if let error { throw error }
        return response
    }
}

private func msg(_ text: String = "are you free Friday?") -> Message {
    Message(id: "m", threadID: "t", sender: "Alice <alice@example.com>",
            recipients: ["me@example.com"], subject: "Lunch",
            date: Date(timeIntervalSince1970: 0), bodyHTML: nil, bodyText: text,
            isUnread: false, labelIDs: [])
}

@MainActor
@Suite struct AssistantViewModelTests {
    @Test func startsIdle() {
        let model = AssistantViewModel(assistant: MailAssistant(provider: ScriptedProvider()))
        #expect(model.state == .idle)
        #expect(model.isAvailable)
    }

    @Test func withNoProviderTheFeatureIsUnavailable() {
        let model = AssistantViewModel(assistant: MailAssistant(provider: nil))
        #expect(!model.isAvailable)
    }

    @Test func summarisingMovesThroughWorkingToAResult() async {
        let model = AssistantViewModel(assistant: MailAssistant(provider: ScriptedProvider("Short summary.")))

        await model.summarize(messages: [msg()])

        #expect(model.state == .result("Short summary."))
    }

    @Test func aFailureBecomesAReadableMessage() async {
        let model = AssistantViewModel(
            assistant: MailAssistant(provider: ScriptedProvider(error: .unavailable)))

        await model.summarize(messages: [msg()])

        guard case let .failed(message) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        // The most common local failure needs to say what to actually do.
        #expect(message.lowercased().contains("ollama") || message.lowercased().contains("reach"))
    }

    @Test func anUnauthorizedFailureTalksAboutTheKeyNotTheDaemon() async {
        let model = AssistantViewModel(
            assistant: MailAssistant(provider: ScriptedProvider(error: .unauthorized)))

        await model.summarize(messages: [msg()])

        guard case let .failed(message) = model.state else {
            Issue.record("expected .failed")
            return
        }
        #expect(message.lowercased().contains("key"))
    }

    @Test func suggestedRepliesArriveAsAList() async {
        let model = AssistantViewModel(
            assistant: MailAssistant(provider: ScriptedProvider("Yes.\nNot Friday.\nLet me check.")))

        await model.suggestReplies(to: [msg()])

        #expect(model.state == .suggestions(["Yes.", "Not Friday.", "Let me check."]))
    }

    @Test func dismissReturnsToIdle() async {
        let model = AssistantViewModel(assistant: MailAssistant(provider: ScriptedProvider("x")))
        await model.summarize(messages: [msg()])

        model.dismiss()

        #expect(model.state == .idle)
    }

    @Test func theProviderNameIsSurfacedSoUsersKnowWhatAnswered() {
        let model = AssistantViewModel(assistant: MailAssistant(provider: ScriptedProvider()))
        #expect(model.providerName == "Scripted (test-model)")
    }

    @Test func rewritingReturnsTheNewTextForTheCaller() async {
        let model = AssistantViewModel(assistant: MailAssistant(provider: ScriptedProvider("Rewritten.")))
        #expect(await model.rewrite("orig", tone: .formal) == "Rewritten.")
    }

    @Test func rewritingReturnsNilOnFailureRatherThanWipingTheDraft() async {
        let model = AssistantViewModel(
            assistant: MailAssistant(provider: ScriptedProvider(error: .unavailable)))
        // Returning "" here would silently delete what the user wrote.
        #expect(await model.rewrite("orig", tone: .formal) == nil)
    }
}
