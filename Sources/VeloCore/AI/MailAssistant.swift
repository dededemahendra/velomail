import Foundation

/// The AI features, as operations over mail.
///
/// Holding an optional provider is deliberate: with none configured every
/// operation fails with `.notConfigured` and `isAvailable` is false, so callers
/// can hide the features rather than offer actions that always error.
public struct MailAssistant: Sendable {
    private let provider: LLMProvider?

    public init(provider: LLMProvider?) {
        self.provider = provider
    }

    public var isAvailable: Bool { provider != nil }

    /// The model behind the answers, for showing the user what replied.
    public var providerName: String? { provider?.displayName }

    // MARK: - Reading

    public func summarize(messages: [Message]) async throws -> String {
        guard !messages.isEmpty else { return "" }   // never spend on an empty thread
        return try await text(MailPrompt.summarize(messages: messages))
    }

    public func suggestReplies(to messages: [Message], count: Int = 3) async throws -> [String] {
        guard !messages.isEmpty else { return [] }
        return Self.lines(in: try await text(MailPrompt.suggestReplies(messages: messages, count: count)))
    }

    public func triage(messages: [Message]) async throws -> MailPriority {
        guard !messages.isEmpty else { return .normal }
        return Self.priority(in: try await text(MailPrompt.triage(messages: messages)))
    }

    // MARK: - Writing

    public func draftReply(to messages: [Message], instruction: String) async throws -> String {
        try await text(MailPrompt.draftReply(messages: messages, instruction: instruction))
    }

    public func rewrite(_ body: String, tone: WritingTone) async throws -> String {
        try await text(MailPrompt.rewrite(body, tone: tone))
    }

    public func fixGrammar(_ body: String) async throws -> String {
        try await text(MailPrompt.fixGrammar(body))
    }

    public func translate(_ body: String, to language: String) async throws -> String {
        try await text(MailPrompt.translate(body, to: language))
    }

    public func subjectLine(body: String) async throws -> String {
        try await text(MailPrompt.subjectLine(body: body))
    }

    // MARK: - Internals

    private func text(_ request: LLMRequest) async throws -> String {
        guard let provider else { throw LLMError.notConfigured }
        return Self.cleaned(try await provider.complete(request))
    }

    /// Strips the two things models reliably add to short answers: a "Here is
    /// the…" preamble, and quotes wrapped around the whole result.
    static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let newline = text.firstIndex(of: "\n") {
            let firstLine = text[text.startIndex..<newline].trimmingCharacters(in: .whitespaces)
            if firstLine.hasSuffix(":") && firstLine.count < 60 {
                text = String(text[text.index(after: newline)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Only a matched pair wrapping the *whole* string; quotes inside the
        // text are the sender's words and must survive.
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\""),
           !text.dropFirst().dropLast().contains("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }

    /// One item per line, tolerating the bullets and numbering models add
    /// despite being asked not to.
    static func lines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^([-*•]|\\d+[.)])\\s+", with: "",
                                          options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// Matches leniently, and defaults to `.normal` -- a mis-parse must never
    /// invent urgency.
    static func priority(in text: String) -> MailPriority {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let word = normalized.components(separatedBy: CharacterSet.letters.inverted)
            .first(where: { !$0.isEmpty }) else { return .normal }
        return MailPriority(rawValue: word) ?? .normal
    }
}
