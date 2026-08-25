import Testing
import Foundation
@testable import VeloCore

@Suite struct SnippetExpansionTests {
    private let library = SnippetLibrary(snippets: [
        Snippet(name: "Thanks", shortcut: "thx", body: "Thanks so much."),
        Snippet(name: "Intro", shortcut: "intro", subject: "Intro call?", body: "Thursday?"),
    ])

    private func expand(_ text: String, at cursor: Int) -> SnippetExpansion.Expansion? {
        SnippetExpansion.expand(in: text, at: cursor, using: library)
    }

    private func typed(_ previous: String, _ current: String) -> SnippetExpansion.Expansion? {
        SnippetExpansion.expandOnTyping(previous: previous, current: current, using: library)
    }

    // MARK: - Expanding at a cursor

    @Test func aShortcutAtTheCursorExpands() {
        #expect(expand(";thx", at: 4)?.text == "Thanks so much.")
    }

    @Test func expansionKeepsTheTextAfterTheCursor() {
        // The cursor is mid-string: only the token behind it is replaced.
        #expect(expand("Hi ;thx and bye", at: 7)?.text == "Hi Thanks so much. and bye")
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(expand(";THX", at: 4)?.text == "Thanks so much.")
    }

    @Test func anUnknownShortcutDoesNotExpand() {
        // Never a prefix match: expanding `;th` into whatever `;thx` holds is
        // guessing at what the user meant.
        #expect(expand(";th", at: 3) == nil)
        #expect(expand(";nope", at: 5) == nil)
    }

    @Test func aSemicolonAloneDoesNotExpand() {
        #expect(expand(";", at: 1) == nil)
    }

    @Test func aSemicolonMidWordIsNotAToken() {
        // A semicolon inside a word is punctuation, not a trigger.
        #expect(expand("foo;thx", at: 7) == nil)
    }

    @Test func aTokenPrecededByWhitespaceExpands() {
        #expect(expand("Hello\n;thx", at: 10)?.text == "Hello\nThanks so much.")
    }

    @Test func whitespaceInsideTheTokenStopsTheScan() {
        #expect(expand("; thx", at: 5) == nil)
    }

    @Test func expansionReportsTheSnippetItUsed() {
        #expect(expand(";intro", at: 6)?.snippet.subject == "Intro call?")
    }

    @Test func anEmptyLibraryNeverExpands() {
        #expect(SnippetExpansion.expand(in: ";thx", at: 4, using: .empty) == nil)
    }

    @Test func aCursorPastTheEndIsRefusedRatherThanTrapping() {
        #expect(expand(";thx", at: 99) == nil)
        #expect(expand(";thx", at: -1) == nil)
    }

    // MARK: - Expanding as you type

    @Test func typingASpaceAfterAShortcutExpandsAndEatsTheSpace() {
        // The boundary is consumed: a snippet ends with its own punctuation far
        // more often than it wants a trailing space.
        #expect(typed(";thx", ";thx ")?.text == "Thanks so much.")
    }

    @Test func typingANewlineAfterAShortcutExpands() {
        #expect(typed(";thx", ";thx\n")?.text == "Thanks so much.")
    }

    @Test func typingATabAfterAShortcutExpands() {
        #expect(typed(";thx", ";thx\t")?.text == "Thanks so much.")
    }

    @Test func typingAnOrdinaryCharacterDoesNotExpand() {
        #expect(typed(";th", ";thx") == nil)
    }

    @Test func aPasteIsNotTyping() {
        // More than one character arrived, so there is no single insertion point
        // to treat as a cursor.
        #expect(typed("", ";thx ") == nil)
    }

    @Test func aDeletionIsNotTyping() {
        #expect(typed(";thx ", ";thx") == nil)
    }

    @Test func aReplacementOfTheSameLengthIsNotTyping() {
        #expect(typed(";thx", ";thy") == nil)
    }

    @Test func typingABoundaryIntoTheMiddleExpandsTheTokenThere() {
        #expect(typed(";thxtail", ";thx tail")?.text == "Thanks so much.tail")
    }

    @Test func typingABoundaryAfterNoTokenIsLeftAlone() {
        #expect(typed("hello", "hello ") == nil)
    }
}
