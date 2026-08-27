import Foundation

/// Something worth asking about before a message goes.
///
/// Deliberately few. A client that questions every send teaches people to
/// dismiss it without reading, which costs more than it saves.
public enum SendWarning: Equatable, Sendable {
    /// The message says a file is attached and none is.
    case missingAttachment
    /// More people than the reader usually writes to.
    case manyRecipients(Int)

    public var question: String {
        switch self {
        case .missingAttachment:
            return "This message mentions an attachment but none is attached."
        case let .manyRecipients(count):
            return "This message goes to \(count) people."
        }
    }

    /// What the button that sends anyway should say.
    public var proceed: String {
        switch self {
        case .missingAttachment: return "Send without it"
        case .manyRecipients: return "Send to all"
        }
    }

    /// The first thing worth pausing over, or nil to send.
    ///
    /// The missing file comes first: it is a mistake, where a large recipient
    /// list is usually a decision.
    public static func check(_ draft: Draft, recipientLimit: Int) -> SendWarning? {
        if mentionsAnAttachment(draft), draft.attachments.isEmpty {
            return .missingAttachment
        }
        let recipients = draft.to.count + draft.cc.count + draft.bcc.count
        if recipientLimit > 0, recipients > recipientLimit {
            return .manyRecipients(recipients)
        }
        return nil
    }

    /// Phrases that claim a file is coming with the message.
    ///
    /// "attached to" is left out on purpose: it is about feelings and fittings
    /// far more often than files.
    private static let claims = [
        "attached is", "attached are", "attached you", "the attached",
        "i attached", "i've attached", "i have attached", "we attached",
        "we've attached", "please find attached", "please find enclosed",
        "see attached", "see the attached", "find attached", "enclosed is",
        "enclosed are", "attaching", "i have included the file",
        "attachment:", "attached:", "see attachment", "the attachment",
        "in the attachment",
    ]

    private static func mentionsAnAttachment(_ draft: Draft) -> Bool {
        // Only what the writer wrote. A reply to "here is the attached
        // invoice" must not nag about a file the other person sent.
        let authored = beforeTheQuote(draft.bodyText) + " " + draft.subject
        let text = authored.lowercased()
        return claims.contains { text.contains($0) }
    }

    /// Everything above the quoted parent, which is where the writer's own
    /// words are.
    private static func beforeTheQuote(_ body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        var authored: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") || trimmed.hasSuffix("wrote:") { break }
            authored.append(line)
        }
        return authored.joined(separator: "\n")
    }
}
