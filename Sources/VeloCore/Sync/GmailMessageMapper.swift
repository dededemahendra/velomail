import Foundation

/// Maps decoded Gmail messages into VeloCore `Message` records and derives the
/// parent `MailThread` from a thread's messages.
public enum GmailMessageMapper {
    /// Maps a single Gmail message to a VeloCore `Message`.
    public static func message(from dto: GmailMessageDTO) -> Message {
        let headers = dto.payload?.headers ?? []
        func header(_ name: String) -> String? {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        func addressList(_ name: String) -> [String] {
            (header(name) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        let recipients = addressList("To")
        let cc = addressList("Cc")

        // `References` is a whitespace-separated list of message ids, not comma-separated.
        let references = (header("References") ?? "")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var html: String?
        var text: String?
        if let payload = dto.payload { collectBodies(payload, html: &html, text: &text) }

        return Message(
            id: dto.id,
            threadID: dto.threadId,
            sender: header("From") ?? "",
            recipients: recipients,
            cc: cc,
            subject: header("Subject") ?? "",
            date: date(from: dto.internalDate),
            bodyHTML: html,
            bodyText: text,
            isUnread: isUnread(dto),
            labelIDs: dto.labelIds ?? [],
            messageIDHeader: header("Message-ID"),
            inReplyTo: header("In-Reply-To"),
            references: references,
            listUnsubscribe: header("List-Unsubscribe"))
    }

    /// Derives the thread record from all of a thread's messages. Returns `nil`
    /// when `dtos` is empty. All `dtos` are assumed to share a `threadId`.
    public static func thread(from dtos: [GmailMessageDTO]) -> MailThread? {
        guard let threadID = dtos.first?.threadId else { return nil }
        let newest = dtos.max { seconds($0.internalDate) < seconds($1.internalDate) }!
        let (labelIDs, isUnread) = threadAggregate(from: dtos.map(message(from:)))

        return MailThread(
            id: threadID,
            sender: message(from: newest).sender,
            snippet: newest.snippet ?? "",
            lastMessageDate: date(from: newest.internalDate),
            isUnread: isUnread,
            hasAttachments: dtos.contains { hasAttachment($0.payload) },
            labelIDs: labelIDs)
    }

    /// Aggregates a thread's per-message labels: the sorted union of all message
    /// labels, and unread iff any message carries `UNREAD`. Shared by backfill
    /// derivation and incremental label-delta re-derivation.
    public static func threadAggregate(from messages: [Message]) -> (labelIDs: [String], isUnread: Bool) {
        let labelIDs = Set(messages.flatMap { $0.labelIDs }).sorted()
        let isUnread = messages.contains { $0.labelIDs.contains("UNREAD") }
        return (labelIDs, isUnread)
    }

    // MARK: - Internals

    private static func isUnread(_ dto: GmailMessageDTO) -> Bool {
        dto.labelIds?.contains("UNREAD") ?? false
    }

    private static func seconds(_ internalDate: String?) -> Double {
        (internalDate.flatMap(Double.init) ?? 0) / 1000
    }

    private static func date(from internalDate: String?) -> Date {
        Date(timeIntervalSince1970: seconds(internalDate))
    }

    /// Walks the MIME tree, capturing the first HTML and first plain-text body.
    private static func collectBodies(_ part: GmailMessageDTO.Part, html: inout String?, text: inout String?) {
        switch part.mimeType?.lowercased() {
        case "text/html" where html == nil:
            html = part.body?.data.flatMap(decodeBase64URL)
        case "text/plain" where text == nil:
            text = part.body?.data.flatMap(decodeBase64URL)
        default:
            break
        }
        for child in part.parts ?? [] { collectBodies(child, html: &html, text: &text) }
    }

    private static func hasAttachment(_ part: GmailMessageDTO.Part?) -> Bool {
        guard let part else { return false }
        if let filename = part.filename, !filename.isEmpty { return true }
        return (part.parts ?? []).contains { hasAttachment($0) }
    }

    /// Decodes Gmail's URL-safe base64 (RFC 4648 §5), tolerating missing padding.
    private static func decodeBase64URL(_ string: String) -> String? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
