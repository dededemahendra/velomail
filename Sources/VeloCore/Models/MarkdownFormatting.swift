import Foundation

/// Applies the marks `MarkdownBody` understands to a stretch of text.
///
/// Pure and index-based, so the rules can be tested without a text view and
/// the editor is left with nothing to do but hand over a string and a range.
public enum MarkdownFormatting {
    public enum Style: Equatable, Sendable, CaseIterable {
        case bold, italic, code, link
        case bullet, numbered, quote

        /// True when the style marks whole lines rather than a span of words.
        var isLineBased: Bool {
            switch self {
            case .bullet, .numbered, .quote: return true
            case .bold, .italic, .code, .link: return false
            }
        }

        var wrapper: String {
            switch self {
            case .bold: return "**"
            case .italic: return "*"
            case .code: return "`"
            default: return ""
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public let text: String
        public let selection: Range<Int>
    }

    public static func apply(_ style: Style, to text: String,
                             selecting range: Range<Int>) -> Result {
        var characters = Array(text)
        let selection = clamp(range, to: characters.count)

        switch style {
        case .link:
            return linked(characters, selection)
        case .bullet, .numbered, .quote:
            return prefixed(style, characters, selection)
        case .bold, .italic, .code:
            return wrapped(style.wrapper, &characters, selection)
        }
    }

    // MARK: - Spans

    /// Adds the marker pair, or takes it away when it is already there.
    ///
    /// A button that only ever adds markers is a trap: the writer presses it
    /// twice and ends up with `****bold****`.
    private static func wrapped(_ mark: String, _ characters: inout [Character],
                                _ selection: Range<Int>) -> Result {
        let width = mark.count
        let marker = Array(mark)
        let before = selection.lowerBound - width
        let after = selection.upperBound

        if before >= 0, after + width <= characters.count,
           Array(characters[before..<selection.lowerBound]) == marker,
           Array(characters[after..<(after + width)]) == marker {
            characters.removeSubrange(after..<(after + width))
            characters.removeSubrange(before..<selection.lowerBound)
            return Result(text: String(characters),
                          selection: before..<(selection.upperBound - width))
        }

        characters.insert(contentsOf: marker, at: selection.upperBound)
        characters.insert(contentsOf: marker, at: selection.lowerBound)
        return Result(text: String(characters),
                      selection: (selection.lowerBound + width)..<(selection.upperBound + width))
    }

    // MARK: - Lines

    /// Puts a marker at the head of every line the selection touches, or takes
    /// them all away when every one already has it.
    private static func prefixed(_ style: Style, _ characters: [Character],
                                 _ selection: Range<Int>) -> Result {
        let text = String(characters)
        let lines = text.components(separatedBy: "\n")
        let touched = lineIndices(covering: selection, in: lines)
        let alreadyMarked = touched.allSatisfy { marker(of: style, on: lines[$0]) != nil }

        var rewritten = lines
        var counter = 1
        for index in touched {
            if alreadyMarked, let existing = marker(of: style, on: lines[index]) {
                rewritten[index] = String(lines[index].dropFirst(existing.count))
            } else if !alreadyMarked {
                rewritten[index] = prefix(for: style, number: counter) + lines[index]
                counter += 1
            }
        }

        let joined = rewritten.joined(separator: "\n")
        // The selection follows the text it was on rather than a character
        // count that no longer means anything.
        let shift = joined.count - text.count
        return Result(text: joined,
                      selection: clamp(selection.lowerBound..<(selection.upperBound + shift),
                                       to: joined.count))
    }

    private static func prefix(for style: Style, number: Int) -> String {
        switch style {
        case .bullet: return "- "
        case .numbered: return "\(number). "
        case .quote: return "> "
        default: return ""
        }
    }

    /// The marker already on `line`, if it carries one of this style's.
    private static func marker(of style: Style, on line: String) -> String? {
        switch style {
        case .bullet: return line.hasPrefix("- ") ? "- " : nil
        case .quote: return line.hasPrefix("> ") ? "> " : nil
        case .numbered:
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
            return String(digits) + ". "
        default: return nil
        }
    }

    /// Which lines a character range covers. A caret sitting at the very start
    /// of a line still counts as being on it.
    private static func lineIndices(covering selection: Range<Int>,
                                    in lines: [String]) -> [Int] {
        var found: [Int] = []
        var start = 0
        for (index, line) in lines.enumerated() {
            let end = start + line.count
            if selection.lowerBound <= end && selection.upperBound >= start {
                found.append(index)
            }
            start = end + 1                     // the newline
        }
        return found.isEmpty ? [0] : found
    }

    // MARK: - Links

    /// `[words](address)`, with the caret left on whichever half the writer
    /// still has to supply.
    private static func linked(_ characters: [Character], _ selection: Range<Int>) -> Result {
        let selected = String(characters[selection])
        var rewritten = characters

        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            rewritten.replaceSubrange(selection, with: Array("[](\(selected))"))
            return Result(text: String(rewritten), selection: (selection.lowerBound + 1)..<(selection.lowerBound + 1))
        }

        rewritten.replaceSubrange(selection, with: Array("[\(selected)]()"))
        let caret = selection.lowerBound + selected.count + 3
        return Result(text: String(rewritten), selection: caret..<caret)
    }

    /// AppKit can hand over a range from before the last edit.
    private static func clamp(_ range: Range<Int>, to length: Int) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), length)
        let upper = min(max(lower, range.upperBound), length)
        return lower..<upper
    }
}
