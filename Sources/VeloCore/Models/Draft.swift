import Foundation

/// A file going out with a draft.
///
/// The bytes travel with it rather than a file path. The outbound queue promises
/// a send survives a restart and a failure without losing anything, and a path
/// breaks that the moment the user moves or deletes the file between hitting
/// send and the drain finishing -- a real gap, given the ten-second undo window.
public struct DraftAttachment: Codable, Equatable, Sendable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    /// Best guess at a type from the extension, for files picked off disk.
    public static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "txt", "md": return "text/plain"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }
}

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
    public var attachments: [DraftAttachment]

    public init(to: [String], cc: [String] = [], bcc: [String] = [],
                subject: String, bodyText: String, bodyHTML: String? = nil,
                threadID: String? = nil, inReplyTo: String? = nil,
                references: [String] = [], attachments: [DraftAttachment] = []) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.threadID = threadID
        self.inReplyTo = inReplyTo
        self.references = references
        self.attachments = attachments
    }

    /// Roughly what Gmail accepts in one `messages.send`, minus the third that
    /// base64 adds. Enforced when a file is attached rather than when the send
    /// fails, because a server error ten seconds later -- after the undo window
    /// shut -- is a much worse experience than being told up front.
    public static let maximumAttachmentBytes = 22 * 1_000_000

    public var attachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }

    public var exceedsAttachmentLimit: Bool { attachmentBytes > Self.maximumAttachmentBytes }

    /// A reply to just the sender of `message`.
    ///
    /// Sets recipients, subject and threading headers only — quoting the parent
    /// body is the caller's job, so `bodyText` is whatever it passes.
    /// - Parameter quoting: append the parent, quoted. Opt-in, because the
    ///   engine should not impose composition policy on every caller.
    public static func reply(to message: Message, from _: String,
                             bodyText: String = "", bodyHTML: String? = nil,
                             quoting: Bool = false) -> Draft {
        let (text, html) = body(bodyText, bodyHTML, quoting: quoting, parent: message)
        return Draft(to: [message.sender],
                     subject: replySubject(message.subject),
                     bodyText: text,
                     bodyHTML: html,
                     threadID: message.threadID,
                     inReplyTo: message.messageIDHeader,
                     references: chainedReferences(of: message))
    }

    /// A reply to the sender plus everyone else on the message, minus the
    /// sending identity. Matching is by bare address, case-insensitively; alias
    /// and `+tag` forms are deliberately not resolved.
    public static func replyAll(to message: Message, from sender: String,
                                bodyText: String = "", bodyHTML: String? = nil,
                                quoting: Bool = false) -> Draft {
        let excluded = Set([normalizedAddress(sender), normalizedAddress(message.sender)])
        var seen = excluded
        let others = (message.recipients + message.cc).filter { address in
            let key = normalizedAddress(address)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        let (text, html) = body(bodyText, bodyHTML, quoting: quoting, parent: message)
        return Draft(to: [message.sender],
                     cc: others,
                     subject: replySubject(message.subject),
                     bodyText: text,
                     bodyHTML: html,
                     threadID: message.threadID,
                     inReplyTo: message.messageIDHeader,
                     references: chainedReferences(of: message))
    }

    // MARK: - Internals

    /// Composes the reply body: what the user wrote, then the quoted parent.
    /// The HTML half is only produced when the parent had HTML, so a plain
    /// conversation stays plain.
    private static func body(_ text: String, _ html: String?,
                             quoting: Bool, parent: Message) -> (String, String?) {
        guard quoting else { return (text, html) }
        let quotedText = "\(text)\n\n\(QuotedReply.text(quoting: parent))"
        guard parent.bodyHTML != nil else { return (quotedText, html) }
        let written = html ?? "<p>\(text)</p>"
        return (quotedText, "\(written)\n\(QuotedReply.html(quoting: parent))")
    }

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
