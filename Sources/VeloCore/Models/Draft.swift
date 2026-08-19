import Foundation

/// An outgoing message not yet handed to Gmail. Pure value type: it carries the
/// recipients, the body, and the threading context needed to make Gmail staple
/// the result onto an existing conversation. It is `Codable` because it is
/// persisted verbatim inside a queued `PendingMutation`, so a send survives a
/// process restart and a failed send can be re-opened.
public struct Draft: Codable, Equatable, Sendable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var bodyText: String
    public var bodyHTML: String?
    /// The Gmail thread to attach to; `nil` for a fresh compose.
    public var threadID: String?
    /// The parent's RFC 5322 `Message-ID`, not its Gmail id.
    public var inReplyTo: String?
    /// The full ancestry, oldest first, ending with `inReplyTo`.
    public var references: [String]

    public init(to: [String], cc: [String] = [], bcc: [String] = [],
                subject: String, bodyText: String, bodyHTML: String? = nil,
                threadID: String? = nil, inReplyTo: String? = nil,
                references: [String] = []) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.threadID = threadID
        self.inReplyTo = inReplyTo
        self.references = references
    }

    /// A reply to just the sender of `message`.
    ///
    /// Sets recipients, subject and threading headers only — quoting the parent
    /// body is the caller's job, so `bodyText` is whatever it passes.
    public static func reply(to message: Message, from _: String,
                             bodyText: String = "", bodyHTML: String? = nil) -> Draft {
        Draft(to: [message.sender],
              subject: replySubject(message.subject),
              bodyText: bodyText,
              bodyHTML: bodyHTML,
              threadID: message.threadID,
              inReplyTo: message.messageIDHeader,
              references: chainedReferences(of: message))
    }

    /// A reply to the sender plus everyone else on the message, minus the
    /// sending identity. Matching is by bare address, case-insensitively; alias
    /// and `+tag` forms are deliberately not resolved.
    public static func replyAll(to message: Message, from sender: String,
                                bodyText: String = "", bodyHTML: String? = nil) -> Draft {
        let excluded = Set([normalizedAddress(sender), normalizedAddress(message.sender)])
        var seen = excluded
        let others = (message.recipients + message.cc).filter { address in
            let key = normalizedAddress(address)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        return Draft(to: [message.sender],
                     cc: others,
                     subject: replySubject(message.subject),
                     bodyText: bodyText,
                     bodyHTML: bodyHTML,
                     threadID: message.threadID,
                     inReplyTo: message.messageIDHeader,
                     references: chainedReferences(of: message))
    }

    // MARK: - Internals

    /// Prefixes `Re: ` unless the subject already carries one, in any case form.
    private static func replySubject(_ subject: String) -> String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }

    /// A reply's `References` is the parent's plus the parent itself. Dropping
    /// this is what breaks long threads in other mail clients.
    private static func chainedReferences(of message: Message) -> [String] {
        guard let parentID = message.messageIDHeader else { return message.references }
        return message.references + [parentID]
    }

    /// Extracts the bare address from a `Display Name <addr>` header value and
    /// lowercases it, so identity comparisons survive display names.
    static func normalizedAddress(_ value: String) -> String {
        guard let open = value.lastIndex(of: "<"),
              let close = value.lastIndex(of: ">"), open < close else {
            return value.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return String(value[value.index(after: open)..<close])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
}
