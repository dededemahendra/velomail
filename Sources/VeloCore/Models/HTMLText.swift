import Foundation

/// Turns HTML-escaped text back into words.
///
/// Gmail returns `snippet` escaped, so a list showed "It&#39;s Friday" to
/// anyone whose correspondents use an apostrophe. Applied when the text is
/// shown rather than when it is stored: the escaped form is what arrived, and
/// decoding on display fixes every row already in the database as well as the
/// next one.
public enum HTMLText {
    public static func decoded(_ text: String) -> String {
        // Nothing to do is the overwhelmingly common case, and this runs once
        // per visible row.
        guard text.contains("&") else { return text }

        var out = text
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return decodingNumeric(out)
    }

    private static let named: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&apos;", "\u{27}"), ("&nbsp;", " "), ("&mdash;", "\u{2014}"),
        ("&ndash;", "\u{2013}"), ("&hellip;", "\u{2026}"),
        ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
        ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
    ]

    /// `&#39;` and `&#x27;`. Senders use whichever their template engine emits.
    ///
    /// An entity that is not a number is left exactly as written: better to
    /// show what arrived than to guess at it and drop the text.
    private static func decodingNumeric(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else {
            return text
        }
        var out = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text),
                  let flag = Range(match.range(at: 1), in: text),
                  let digits = Range(match.range(at: 2), in: text) else { continue }
            let radix = text[flag].isEmpty ? 10 : 16
            guard let value = UInt32(text[digits], radix: radix),
                  let scalar = Unicode.Scalar(value) else { continue }
            out.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return out
    }
}
