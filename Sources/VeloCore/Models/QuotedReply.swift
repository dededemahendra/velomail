import Foundation

/// Builds the quoted portion of a reply.
///
/// The format matters more than it looks: recipients read it in *their* client,
/// not ours, so it follows the attribution-plus-quote convention every mail
/// client emits and parses.
public enum QuotedReply {
    /// `On <date>, <sender> wrote:` followed by the parent body, `> ` per line.
    public static func text(quoting message: Message) -> String {
        let body = message.bodyText ?? strippedTags(from: message.bodyHTML ?? "")
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
    private static func strippedTags(from html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
