import Testing
@testable import VeloCore

@Suite struct KeyInputTests {
    @Test func chordsAreEqualOnlyWhenKeyAndModifiersMatch() {
        #expect(KeyInput(.character("j")) == KeyInput(.character("j")))
        #expect(KeyInput(.character("j")) != KeyInput(.character("k")))
        #expect(KeyInput(.enter) != KeyInput(.enter, [.command]))
    }

    @Test func charactersAreComparedCaseInsensitively() {
        // A binding on "j" must still fire when shift-lock is on.
        #expect(KeyInput(.character("J")) == KeyInput(.character("j")))
    }

    @Test func modifiersCombine() {
        let both: KeyInput.Modifiers = [.command, .shift]
        #expect(both.contains(.command))
        #expect(both.contains(.shift))
        #expect(!KeyInput.Modifiers.command.contains(.shift))
    }

    @Test func aChordWithoutModifiersHasNone() {
        #expect(KeyInput(.character("e")).modifiers.isEmpty)
    }

    @Test func mailActionsAreDistinct() {
        #expect(MailAction.archiveSelected != MailAction.openSelected)
        #expect(MailAction.moveSelectionDown != MailAction.moveSelectionUp)
    }
}
