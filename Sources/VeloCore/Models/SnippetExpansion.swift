import Foundation

/// Turning `;shortcut` into a snippet body. Pure, and deliberately so: the
/// composer's editor is a SwiftUI `TextEditor`, which exposes no selection, so
/// the one thing that must be correct — *which* token is being expanded — is
/// tested without a window anywhere near it.
public enum SnippetExpansion {
    public struct Expansion: Equatable, Sendable {
        /// The whole body text after the token was replaced.
        public let text: String
        /// What it expanded into, so the caller can also fill an empty subject.
        public let snippet: Snippet

        public init(text: String, snippet: Snippet) {
            self.text = text
            self.snippet = snippet
        }
    }

    /// Expands the `;shortcut` ending at `cursor`, a character offset.
    ///
    /// Returns nil unless the token is real and matches exactly. Matching is
    /// never by prefix: expanding `;th` into whatever `;thx` holds would be
    /// guessing at what the user meant.
    public static func expand(in text: String, at cursor: Int,
                              using library: SnippetLibrary) -> Expansion? {
        let characters = Array(text)
        guard cursor >= 0, cursor <= characters.count else { return nil }

        // Scan back for the `;`, giving up at the first whitespace — a token
        // with a space in it is not a token.
        var start = cursor - 1
        while start >= 0, !characters[start].isWhitespace, characters[start] != ";" {
            start -= 1
        }
        guard start >= 0, characters[start] == ";" else { return nil }

        // The `;` has to start a word. Mid-word it is punctuation, not a trigger.
        guard start == 0 || characters[start - 1].isWhitespace else { return nil }

        let shortcut = String(characters[(start + 1)..<cursor])
        guard !shortcut.isEmpty, let snippet = library.snippet(forShortcut: shortcut) else { return nil }

        return Expansion(
            text: String(characters[0..<start]) + snippet.body + String(characters[cursor...]),
            snippet: snippet)
    }

    /// Expands after the single character just typed, when that character is a
    /// word boundary.
    ///
    /// This is how the cursor is recovered without the editor's help: one
    /// inserted character identifies its own position, and that position is the
    /// cursor. A paste, a deletion or a programmatic assignment is not a single
    /// typed character, so none of them can trigger an expansion.
    ///
    /// The boundary is consumed, which falls out of removing it before
    /// expanding: a snippet ends with its own punctuation far more often than it
    /// wants a trailing space.
    public static func expandOnTyping(previous: String, current: String,
                                      using library: SnippetLibrary) -> Expansion? {
        let old = Array(previous)
        let new = Array(current)
        guard new.count == old.count + 1 else { return nil }

        var insertion = 0
        while insertion < old.count, old[insertion] == new[insertion] { insertion += 1 }
        guard new[insertion].isWhitespace else { return nil }
        // Everything after the insertion has to be untouched, or this was an
        // edit that merely happens to be one character longer.
        guard Array(new[(insertion + 1)...]) == Array(old[insertion...]) else { return nil }

        var withoutBoundary = new
        withoutBoundary.remove(at: insertion)
        return expand(in: String(withoutBoundary), at: insertion, using: library)
    }
}
