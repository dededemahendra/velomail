import Foundation
import SwiftUI
import VeloCore

/// Drives the AI panel: one operation at a time, with a state the UI can render.
@MainActor
public final class AssistantViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case working
        case result(String)
        /// Waiting for the user to say what the reply should do.
        case prompting
        /// A written reply, kept distinct from `result` so the panel can offer
        /// "Use this" for a draft and never for a summary.
        case draft(String)
        case suggestions([String])
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    /// What the reply should do, in the user's words.
    @Published public var instruction: String = ""

    private let assistant: MailAssistant

    public init(assistant: MailAssistant) {
        self.assistant = assistant
    }

    public var isAvailable: Bool { assistant.isAvailable }
    public var providerName: String? { assistant.providerName }

    public func dismiss() {
        state = .idle
        instruction = ""
    }

    /// Asks what the reply should say.
    ///
    /// Nothing happens without a provider: offering to write something it
    /// cannot write is worse than not offering.
    public func beginDraft() {
        guard isAvailable else { return }
        instruction = ""
        state = .prompting
    }

    /// Writes a reply following `instruction`.
    public func runDraft(messages: [Message]) async {
        let asked = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        // No instruction, nothing to act on -- and no call to spend.
        guard !asked.isEmpty else { return }
        await run { .draft(try await assistant.draftReply(to: messages, instruction: asked)) }
    }

    public func summarize(messages: [Message]) async {
        await run { .result(try await assistant.summarize(messages: messages)) }
    }

    public func suggestReplies(to messages: [Message]) async {
        await run { .suggestions(try await assistant.suggestReplies(to: messages)) }
    }

    public func triage(messages: [Message]) async {
        await run { .result(try await assistant.triage(messages: messages).rawValue) }
    }

    public func draftReply(to messages: [Message], instruction: String) async {
        await run { .result(try await assistant.draftReply(to: messages, instruction: instruction)) }
    }

    /// Returns the transformed text, or `nil` on failure.
    ///
    /// Nil rather than an empty string on purpose: these results replace what
    /// the user has typed, and returning "" would silently delete their draft.
    public func rewrite(_ body: String, tone: WritingTone) async -> String? {
        await transform { try await assistant.rewrite(body, tone: tone) }
    }

    public func fixGrammar(_ body: String) async -> String? {
        await transform { try await assistant.fixGrammar(body) }
    }

    public func translate(_ body: String, to language: String) async -> String? {
        await transform { try await assistant.translate(body, to: language) }
    }

    public func subjectLine(body: String) async -> String? {
        await transform { try await assistant.subjectLine(body: body) }
    }

    // MARK: - Internals

    private func run(_ operation: () async throws -> State) async {
        state = .working
        do {
            state = try await operation()
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    private func transform(_ operation: () async throws -> String) async -> String? {
        state = .working
        do {
            let text = try await operation()
            state = .idle
            return text
        } catch {
            state = .failed(Self.describe(error))
            return nil
        }
    }

    /// Each failure gets words that say what to do about it. "Something went
    /// wrong" for a daemon that is not running would waste the user's time.
    static func describe(_ error: Error) -> String {
        guard let error = error as? LLMError else { return "Assistant failed." }
        switch error {
        case .notConfigured:
            return "No AI provider configured. Set an API key, or run Ollama locally."
        case .unauthorized:
            return "The API key was rejected. Check VELOMAIL_ANTHROPIC_API_KEY."
        case .unavailable:
            return "Could not reach the model. If you are using Ollama, check it is running."
        case let .server(status, message):
            return message.map { "Model error (\(status)): \($0)" } ?? "Model error (\(status))."
        case .malformedResponse:
            return "The model returned something unreadable."
        }
    }
}
