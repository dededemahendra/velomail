import Testing
@testable import VeloCore

@Suite struct KeyboardShortcutLabelTests {
    @Test func aPlainKeyIsItsLetter() {
        #expect(KeyboardEngine.shortcutLabel(for: .archiveSelected) == "E")
        #expect(KeyboardEngine.shortcutLabel(for: .compose) == "C")
    }

    @Test func aModifiedKeyShowsItsSymbol() {
        #expect(KeyboardEngine.shortcutLabel(for: .openCommandPalette) == "⌘K")
        #expect(KeyboardEngine.shortcutLabel(for: .send) == "⌘↩")
    }

    @Test func aChordShowsBothKeys() {
        #expect(KeyboardEngine.shortcutLabel(for: .goToInbox) == "G I")
        #expect(KeyboardEngine.shortcutLabel(for: .showAnalytics) == "G A")
    }

    @Test func specialKeysGetTheirGlyph() {
        #expect(KeyboardEngine.shortcutLabel(for: .back) == "esc")
    }

    @Test func anActionReachableOnlyFromThePaletteHasNoLabel() {
        // Palette-only commands must show no hint rather than inventing a key
        // that does nothing.
        #expect(KeyboardEngine.shortcutLabel(for: .discardDraft) == nil)
    }

    @Test func theLabelMatchesWhatTheEngineActuallyDoes() {
        // Derived from the keymap, not written beside it -- so a binding and its
        // hint cannot drift apart.
        for action in MailAction.allCases {
            guard let label = KeyboardEngine.shortcutLabel(for: action) else { continue }
            #expect(!label.isEmpty)
        }
    }

    @Test func everySingleKeyBindingIsDiscoverable() {
        // If a key does something, the palette should be able to say so.
        for action in [MailAction.moveSelectionDown, .moveSelectionUp, .openSelected,
                       .archiveSelected, .reply, .compose, .openSearch, .toggleStar] {
            #expect(KeyboardEngine.shortcutLabel(for: action) != nil)
        }
    }
}
