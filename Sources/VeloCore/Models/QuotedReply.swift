import Foundation

/// Builds the quoted portion of a reply.
///
/// The format matters more than it looks: recipients read it in *their* client,
/// not ours, so it follows the attribution-plus-quote convention every mail
/// client emits and parses.
public enum QuotedReply {
    /// `On <date>, <sender> wrote:` followed by the parent body, `> ` per line.
    public static func text(quoting message: Message) -> String {
        let body = message.bodyText ?? strippedTags(message.bodyHTML ?? "")
        let quoted = body
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
        return "\(attribution(for: message))\n\(quoted)"
    }

    /// The same attribution, with the parent body inside a `<blockquote>`.
    public static func html(quoting message: Message) -> String {
        let body = message.bodyHTML ?? "<p>\(escaped(message.bodyText ?? ""))</p>"
        return """
        <p>\(escaped(attribution(for: message)))</p>
        <blockquote style="margin:0 0 0 12px;padding-left:12px;border-left:2px solid #ccc">
        \(body)
        </blockquote>
        """
    }

    /// The block a forward puts above the original: the standard header set,
    /// so the reader can see who sent it, to whom, and when.
    public static func forwardedText(_ message: Message) -> String {
        var lines = ["---------- Forwarded message ----------",
                     "From: \(message.sender)",
                     "Date: \(dateFormatter.string(from: message.date))",
                     "Subject: \(message.subject)"]
        if !message.recipients.isEmpty {
            lines.append("To: \(message.recipients.joined(separator: ", "))")
        }
        if !message.cc.isEmpty {
            lines.append("Cc: \(message.cc.joined(separator: ", "))")
        }
        let body = message.bodyText ?? strippedTags(message.bodyHTML ?? "")
        return lines.joined(separator: "\n") + "\n\n" + body
    }

    public static func forwardedHTML(_ message: Message) -> String {
        let header = forwardedText(message)
            .components(separatedBy: "\n\n").first ?? ""
        let body = message.bodyHTML ?? "<p>\(escaped(message.bodyText ?? ""))</p>"
        return """
        <div><pre>\(escaped(header))</pre></div>
        \(body)
        """
    }

    // MARK: - Internals

    static func attribution(for message: Message) -> String {
        "On \(dateFormatter.string(from: message.date)), \(message.sender) wrote:"
    }

    /// Fixed-format and POSIX-locale, so the line other clients parse does not
    /// change shape with the sender's region settings.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm"
        return formatter
    }()

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Crude de-HTML for quoting an HTML-only parent as plain text.
    static func strippedTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
