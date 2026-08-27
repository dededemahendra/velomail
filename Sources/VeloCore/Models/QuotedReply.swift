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
        let quoted = collapsingBlankRuns(in: body)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
        return "\(attribution(for: message))\n\(quoted)"
    }

    /// The quoted body as something to read, for a composer showing the writer
    /// what they are about to send along.
    ///
    /// Not what goes on the wire. Quoting is no place to edit what somebody
    /// wrote, but a preview is only ever read, so it can drop the parts of a
    /// marketing email that exist for the sender's analytics rather than for
    /// anyone's eyes.
    public static func preview(of message: Message) -> String {
        // An HTML message's plain half is a machine's rendering of it, with
        // every link expanded inline. The rendered text is what the reader was
        // looking at a moment ago.
        let body = message.bodyHTML.map(strippedTags) ?? message.bodyText ?? ""
        return collapsingBlankRuns(in: shortenedLinks(in: body)).joined(separator: "\n")
    }

    /// Lines with runs of blank ones flattened to a single break, and none left
    /// trailing. A marketing email's plain half is double-spaced throughout, so
    /// every paragraph arrived with two or three empty quote markers under it.
    private static func collapsingBlankRuns(in body: String) -> [String] {
        var lines: [String] = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty && lines.last?.isEmpty == true { continue }
            lines.append(trimmed.isEmpty ? "" : line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// How much of a URL is worth reading before it is just a token.
    private static let readableURLLength = 48

    /// Replaces tracking URLs with their host, so a line of prose is legible
    /// again. Anything short enough to read is left as it is.
    private static func shortenedLinks(in body: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s)\\]]+") else { return body }
        var out = body
        let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: body) else { continue }
            let url = String(body[range])
            guard url.count > readableURLLength,
                  let host = URL(string: url)?.host else { continue }
            let scheme = url.hasPrefix("https") ? "https" : "http"
            out.replaceSubrange(range, with: "\(scheme)://\(host)/\u{2026}")
        }
        return out
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

    /// The readable prose of an HTML message.
    ///
    /// Order matters. Removing `<style>` and `</style>` as tags leaves the CSS
    /// between them standing as text, and a newsletter carries kilobytes of
    /// `@font-face` rules -- which is exactly what a quote filled up with. The
    /// blocks whose contents are not prose go first, whole.
    static func strippedTags(_ html: String) -> String {
        var text = html
        for tag in ["style", "script", "head"] {
            text = removingBlock(tag, from: text)
        }
        // Before the block breaks go in, not after: a newline in HTML source is
        // insignificant -- the reader sees a space -- so collapsing everything
        // first is what tells the two kinds of break apart.
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Block elements are where a reader does see a line end; without this
        // every paragraph runs into the next one.
        text = text.replacingOccurrences(
            of: "</(p|div|tr|li|h[1-6]|blockquote)>|<br\\s*/?>", with: "\n",
            options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodingEntities(text)
        text = removingInvisibles(text)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops `<tag ...>…</tag>` entirely, contents and all.
    ///
    /// An unclosed tag takes only itself: malformed markup is normal in mail,
    /// and losing the whole message over one is not an acceptable trade.
    private static func removingBlock(_ tag: String, from html: String) -> String {
        html.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>", with: "",
                                  options: [.regularExpression, .caseInsensitive])
    }

    /// Characters a mail client never draws, and neither should a quote.
    ///
    /// Newsletters pad the inbox preview line with hundreds of soft hyphens
    /// and joiners. They are invisible where they were meant to be read, so a
    /// quote that shows them is showing markup, not words.
    /// Scalars, not characters: a combining joiner merges with the character
    /// before it into one grapheme, so it is never a `Character` of its own and
    /// filtering at that level silently does nothing.
    private static let invisibles: Set<Unicode.Scalar> = [
        "\u{00AD}",            // soft hyphen
        "\u{034F}",            // combining grapheme joiner
        "\u{200B}", "\u{200C}", "\u{200D}",   // zero-width space, non-joiner, joiner
        "\u{2060}",            // word joiner
        "\u{FEFF}",            // byte order mark
    ]

    private static func removingInvisibles(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !invisibles.contains($0) }))
    }

    private static func decodingEntities(_ text: String) -> String {
        var out = text
        for (entity, character) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
                                    ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "\u{27}"),
                                    ("&apos;", "\u{27}"), ("&mdash;", "\u{2014}"),
                                    ("&ndash;", "\u{2013}"), ("&hellip;", "\u{2026}"),
                                    ("&shy;", "\u{00AD}"), ("&zwnj;", "\u{200C}"),
                                    ("&zwj;", "\u{200D}")] {
            out = out.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return out
    }
}
