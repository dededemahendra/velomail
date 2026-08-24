import Foundation

/// How much of a message to send. A newsletter can be hundreds of kilobytes and
/// the answer does not improve past the first few paragraphs -- while the whole
/// thing costs either money or local latency.
public let defaultPerMessageLimit = 4_000

/// The tones `rewrite` can target.
public enum WritingTone: String, CaseIterable, Equatable, Sendable {
    case formal, casual, direct, friendly, apologetic, assertive
}

/// How urgent a thread looks. Deliberately small: a scale nobody can act on
/// differently is just decoration.
public enum MailPriority: String, CaseIterable, Equatable, Sendable {
    case urgent, normal, low
}

/// Builds the prompts. Pure, so what gets sent is assertable without a model --
/// which matters, because what goes in the prompt *is* the privacy question.
public enum MailPrompt {
    /// Renders messages as a plain-text conversation.
    public static func transcript(of messages: [Message],
                                  perMessageLimit: Int = defaultPerMessageLimit) -> String {
        messages.map { message in
            let body = truncate(plainText(of: message), to: perMessageLimit)
            return """
            From: \(message.sender)
            Date: \(message.date.formatted(date: .abbreviated, time: .shortened))

            \(body)
            """
        }.joined(separator: "\n\n---\n\n")
    }

    public static func summarize(messages: [Message]) -> LLMRequest {
        LLMRequest(
            system: "You summarise email for a busy reader. Be specific and brief. "
                + "Lead with what is being asked of the reader, if anything.",
            prompt: """
            Summarise this email thread in at most three sentences. \
            Then, on a new line starting with "Action:", state what the reader \
            needs to do, or "Action: none".

            Subject: \(subject(of: messages))

            \(transcript(of: messages))
            """,
            maxTokens: 400)
    }

    public static func suggestReplies(messages: [Message], count: Int = 3) -> LLMRequest {
        LLMRequest(
            system: "You draft short email replies in the reader's voice. "
                + "No greeting, no sign-off, no preamble.",
            prompt: """
            Write \(count) distinct one-sentence replies to this thread, \
            covering different plausible responses. \
            Output them one per line, with nothing else.

            \(transcript(of: messages))
            """,
            maxTokens: 300)
    }

    public static func draftReply(messages: [Message], instruction: String) -> LLMRequest {
        LLMRequest(
            system: "You write email replies. Match the register of the thread. "
                + "Output only the body, with no subject line and no preamble.",
            prompt: """
            Write a reply to this thread. The sender wants it to: \(instruction)

            \(transcript(of: messages))
            """,
            maxTokens: 800)
    }

    public static func rewrite(_ text: String, tone: WritingTone) -> LLMRequest {
        LLMRequest(
            system: "You rewrite email text. Preserve every fact and request. "
                + "Output only the rewritten text.",
            prompt: """
            Rewrite the following to be \(description(of: tone)).

            \(text)
            """,
            maxTokens: 800)
    }

    public static func fixGrammar(_ text: String) -> LLMRequest {
        LLMRequest(
            system: "You correct grammar and spelling without changing meaning, "
                + "tone or word choice beyond what the correction requires. "
                + "Output only the corrected text.",
            prompt: text,
            maxTokens: 800)
    }

    public static func translate(_ text: String, to language: String) -> LLMRequest {
        LLMRequest(
            system: "You translate email. Preserve tone and formatting. "
                + "Output only the translation.",
            prompt: """
            Translate the following into \(language).

            \(text)
            """,
            maxTokens: 1_000)
    }

    public static func subjectLine(body: String) -> LLMRequest {
        LLMRequest(
            system: "You write email subject lines: specific, under eight words, "
                + "no clickbait. Output only the subject line.",
            prompt: """
            Write a subject line for this email.

            \(truncate(body, to: 2_000))
            """,
            maxTokens: 64)
    }

    public static func triage(messages: [Message]) -> LLMRequest {
        let options = MailPriority.allCases.map(\.rawValue).joined(separator: ", ")
        return LLMRequest(
            system: "You classify email urgency. Answer with one word and nothing else.",
            prompt: """
            Classify how urgent this thread is for the recipient. \
            Answer with exactly one of: \(options).

            \(transcript(of: messages))
            """,
            maxTokens: 16)
    }

    // MARK: - Internals

    /// Each tone gets wording of its own; a tone that reads like another is a
    /// menu item that does nothing.
    private static func description(of tone: WritingTone) -> String {
        switch tone {
        case .formal: return "more formal and professional, without being stiff"
        case .casual: return "more casual and conversational"
        case .direct: return "shorter and more direct, cutting hedging"
        case .friendly: return "warmer and friendlier, without losing clarity"
        case .apologetic: return "apologetic and accommodating in tone"
        case .assertive: return "more assertive and confident, without being rude"
        }
    }

    private static func subject(of messages: [Message]) -> String {
        messages.last?.subject ?? messages.first?.subject ?? "(no subject)"
    }

    /// Plain text if the message has it; otherwise de-tagged HTML.
    private static func plainText(of message: Message) -> String {
        if let text = message.bodyText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return strippedHTML(message.bodyHTML ?? "")
    }

    private static func strippedHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(\\s*\\n\\s*){3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncation is announced, so the model knows it is looking at part of
    /// something rather than a sentence that simply stops.
    private static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…[truncated]"
    }
}
