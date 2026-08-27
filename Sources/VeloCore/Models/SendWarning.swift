import Foundation

/// Something worth asking about before a message goes.
///
/// Deliberately few. A client that questions every send teaches people to
/// dismiss it without reading, which costs more than it saves.
public enum SendWarning: Equatable, Sendable {
    /// An address Gmail will refuse. Caught here because the refusal
    /// otherwise arrives long after the window has closed and the undo window
    /// has run out, as a line in the failure queue.
    case malformedAddress(String)
    /// The message says a file is attached and none is.
    case missingAttachment
    /// Nothing on the subject line.
    case noSubject
    /// More people than the reader usually writes to.
    case manyRecipients(Int)

    public var question: String {
        switch self {
        case let .malformedAddress(address):
            return "\u{201C}\(address)\u{201D} is not an email address."
        case .missingAttachment:
            return "This message mentions an attachment but none is attached."
        case .noSubject:
            return "This message has no subject."
        case let .manyRecipients(count):
            return "This message goes to \(count) people."
        }
    }

    /// What the button that sends anyway should say.
    public var proceed: String {
        switch self {
        // Still offered rather than blocked: `isDeliverable` is a guess about
        // someone else's address, and being wrong must cost a keystroke, not
        // the message.
        case .malformedAddress: return "Send anyway"
        case .missingAttachment: return "Send without it"
        case .noSubject: return "Send without one"
        case .manyRecipients: return "Send to all"
        }
    }

    /// The first thing worth pausing over, or nil to send.
    ///
    /// The missing file comes first: it is a mistake, where a large recipient
    /// list is usually a decision.
    public static func check(_ draft: Draft, recipientLimit: Int) -> SendWarning? {
        // Before everything else: this one is certain to fail, where the rest
        // are judgement calls.
        if let bad = (draft.to + draft.cc + draft.bcc).first(where: { !isDeliverable($0) }) {
            return .malformedAddress(bad)
        }
        if mentionsAnAttachment(draft), draft.attachments.isEmpty {
            return .missingAttachment
        }
        let recipients = draft.to.count + draft.cc.count + draft.bcc.count
        if recipientLimit > 0, recipients > recipientLimit {
            return .manyRecipients(recipients)
        }
        // Last: a missing subject is a discourtesy, not a mistake.
        if draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .noSubject
        }
        return nil
    }

    /// Whether an address has the shape Gmail will accept.
    ///
    /// Deliberately loose: exactly one @ with something either side and a dot
    /// in the domain. Anything stricter starts rejecting addresses that work,
    /// which is a far worse failure than letting a rare odd one through.
    static func isDeliverable(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        // A display name is stripped before this in the normal path, but a
        // pasted "Peta <peta@example.com>" must not be called malformed.
        let bare = trimmed.hasSuffix(">")
            ? String(trimmed.drop(while: { $0 != "<" }).dropFirst().dropLast())
            : trimmed
        let parts = bare.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard let dot = domain.firstIndex(of: "."), dot != domain.startIndex else { return false }
        return domain.index(after: dot) != domain.endIndex
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
