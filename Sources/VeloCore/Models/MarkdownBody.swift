import Foundation

/// Turns the light markup people already type in email into HTML.
///
/// This is deliberately not a Markdown implementation. It covers the marks
/// that show up in real messages -- bold, italics, code, links, lists, quotes
/// -- and leaves everything else as literal text. A message with no marks in
/// it produces no HTML at all, so plain mail stays plain on the wire.
///
/// The input is user prose, never source. Every character that is not part of
/// a recognised mark is escaped, so typing `<script>` sends those characters
/// rather than a tag.
public enum MarkdownBody {
    /// The HTML for `markdown`, or nil when there is nothing to format.
    public static func html(from markdown: String) -> String? {
        var formatted = false
        let blocks = self.blocks(of: markdown)
        guard !blocks.isEmpty else { return nil }
        let rendered = blocks.map { render($0, formatted: &formatted) }
        return formatted ? rendered.joined(separator: "\n") : nil
    }

    /// True when the text carries marks worth sending as HTML.
    public static func isFormatted(_ markdown: String) -> Bool {
        html(from: markdown) != nil
    }

    // MARK: - Blocks

    private enum Block {
        case paragraph([String])
        case bullets([String])
        case numbers([String])
        case quote([String])
    }

    /// Groups lines into blocks, ending a run at a blank line or a change of kind.
    private static func blocks(of markdown: String) -> [Block] {
        var blocks: [Block] = []
        var lines: [String] = []
        var kind: Int = 0

        func flush() {
            guard !lines.isEmpty else { return }
            switch kind {
            case 1: blocks.append(.bullets(lines))
            case 2: blocks.append(.numbers(lines))
            case 3: blocks.append(.quote(lines))
            default: blocks.append(.paragraph(lines))
            }
            lines = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { flush(); continue }
            let (lineKind, content) = classify(trimmed)
            if lineKind != kind { flush(); kind = lineKind }
            lines.append(content)
        }
        flush()
        return blocks
    }

    /// The kind of a single line, and the text left once its marker is removed.
    private static func classify(_ line: String) -> (Int, String) {
        if let rest = strip(prefix: "- ", from: line) ?? strip(prefix: "* ", from: line) {
            return (1, rest)
        }
        if let rest = numberedContent(of: line) { return (2, rest) }
        if let rest = strip(prefix: "> ", from: line) ?? (line == ">" ? "" : nil) {
            return (3, rest)
        }
        return (0, line)
    }

    private static func strip(prefix: String, from line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let rest = String(line.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }

    /// The text after a `1. ` style marker, if the line has one.
    private static func numberedContent(of line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        let content = String(rest.dropFirst(2))
        return content.isEmpty ? nil : content
    }

    private static func render(_ block: Block, formatted: inout Bool) -> String {
        switch block {
        case let .paragraph(lines):
            let body = lines.map { inline($0, formatted: &formatted) }.joined(separator: "<br>\n")
            return "<p>\(body)</p>"
        case let .bullets(lines):
            formatted = true
            return list("ul", lines, formatted: &formatted)
        case let .numbers(lines):
            formatted = true
            return list("ol", lines, formatted: &formatted)
        case let .quote(lines):
            formatted = true
            let body = lines.map { inline($0, formatted: &formatted) }.joined(separator: "<br>\n")
            return "<blockquote>\(body)</blockquote>"
        }
    }

    private static func list(_ tag: String, _ lines: [String], formatted: inout Bool) -> String {
        let items = lines.map { "  <li>\(inline($0, formatted: &formatted))</li>" }
        return (["<\(tag)>"] + items + ["</\(tag)>"]).joined(separator: "\n")
    }

    // MARK: - Inline

    /// Scans one line, emitting escaped text and the tags its marks call for.
    private static func inline(_ text: String, formatted: inout Bool) -> String {
        var out = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character == "`",
               let close = text.range(of: "`", range: text.index(after: index)..<text.endIndex) {
                let content = String(text[text.index(after: index)..<close.lowerBound])
                out += "<code>\(escape(content))</code>"
                index = close.upperBound
                formatted = true
                continue
            }

            if text[index...].hasPrefix("**"),
               let close = closing("**", in: text, after: text.index(index, offsetBy: 2)) {
                let start = text.index(index, offsetBy: 2)
                out += "<strong>\(inline(String(text[start..<close]), formatted: &formatted))</strong>"
                index = text.index(close, offsetBy: 2)
                formatted = true
                continue
            }

            if character == "*", let close = closing("*", in: text, after: text.index(after: index)) {
                let start = text.index(after: index)
                out += "<em>\(inline(String(text[start..<close]), formatted: &formatted))</em>"
                index = text.index(after: close)
                formatted = true
                continue
            }

            if character == "[", let link = link(in: text, from: index) {
                out += link.html(&formatted)
                index = link.end
                formatted = true
                continue
            }

            if let bare = bareURL(in: text, from: index) {
                let url = escape(bare.url)
                out += #"<a href="\#(url)">\#(url)</a>"#
                index = bare.end
                formatted = true
                continue
            }

            out += escape(String(character))
            index = text.index(after: index)
        }
        return out
    }

    /// The start of the closing `mark`, if it closes a non-empty span.
    ///
    /// Emphasis has to hug its text: `2 * 3 * 4` is arithmetic, not italics.
    private static func closing(_ mark: String, in text: String,
                                after start: String.Index) -> String.Index? {
        guard start < text.endIndex, !text[start].isWhitespace else { return nil }
        var search = start
        while let found = text.range(of: mark, range: search..<text.endIndex) {
            let before = text[text.index(before: found.lowerBound)]
            if found.lowerBound > start, !before.isWhitespace { return found.lowerBound }
            search = found.upperBound
            guard search < text.endIndex else { return nil }
        }
        return nil
    }

    private struct Link {
        let label: String
        let target: String?
        let end: String.Index

        /// Renders the link, or just its words when the target is not safe to follow.
        func html(_ formatted: inout Bool) -> String {
            let words = MarkdownBody.inline(label, formatted: &formatted)
            guard let target else { return words }
            return #"<a href="\#(MarkdownBody.escape(target))">\#(words)</a>"#
        }
    }

    /// Parses `[label](target)` starting at `start`.
    private static func link(in text: String, from start: String.Index) -> Link? {
        guard let labelEnd = text.range(of: "](", range: start..<text.endIndex),
              let close = text.range(of: ")", range: labelEnd.upperBound..<text.endIndex)
        else { return nil }
        let label = String(text[text.index(after: start)..<labelEnd.lowerBound])
        let target = String(text[labelEnd.upperBound..<close.lowerBound])
        guard !label.isEmpty else { return nil }
        return Link(label: label, target: safeTarget(target), end: close.upperBound)
    }

    /// Schemes a mail client should be willing to hand a reader.
    ///
    /// Anything else -- `javascript:`, `data:`, `file:` -- is dropped rather
    /// than linked: the words survive, the trap does not.
    private static func safeTarget(_ target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
        let lowered = trimmed.lowercased()
        for scheme in ["https://", "http://", "mailto:"] where lowered.hasPrefix(scheme) {
            return trimmed
        }
        return nil
    }

    /// A bare `https://...` run starting at `start`, if one begins there.
    private static func bareURL(in text: String, from start: String.Index) -> (url: String, end: String.Index)? {
        let rest = text[start...]
        guard rest.hasPrefix("https://") || rest.hasPrefix("http://") else { return nil }
        if start > text.startIndex, !text[text.index(before: start)].isWhitespace { return nil }
        var end = start
        while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
        // Sentences end in punctuation; URLs rarely do.
        while end > start, ".,;:!?)\"'".contains(text[text.index(before: end)]) {
            end = text.index(before: end)
        }
        let url = String(text[start..<end])
        return url.count > 8 ? (url, end) : nil
    }

    /// Escapes text so it reads as the characters typed, never as markup.
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }
}
