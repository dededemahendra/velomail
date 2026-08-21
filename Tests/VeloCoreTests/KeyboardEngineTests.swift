import Testing
@testable import VeloCore

@Suite struct KeyboardEngineTests {
    private func engine() -> KeyboardEngine { KeyboardEngine() }

    private func action(_ inputs: [KeyInput]) -> MailAction? {
        var engine = KeyboardEngine()
        var last: KeyboardEngine.Outcome = .unhandled
        for input in inputs { last = engine.handle(input) }
        if case let .action(action) = last { return action }
        return nil
    }

    @Test func mapsTheSingleKeyBindings() {
        #expect(action([KeyInput(.character("j"))]) == .moveSelectionDown)
        #expect(action([KeyInput(.character("k"))]) == .moveSelectionUp)
        #expect(action([KeyInput(.character("o"))]) == .openSelected)
        #expect(action([KeyInput(.enter)]) == .openSelected)
        #expect(action([KeyInput(.character("e"))]) == .archiveSelected)
        #expect(action([KeyInput(.character("r"))]) == .reply)
        #expect(action([KeyInput(.character("c"))]) == .compose)
    }

    @Test func mapsTheModifiedBindings() {
        #expect(action([KeyInput(.enter, [.command])]) == .send)
        #expect(action([KeyInput(.character("k"), [.command])]) == .openCommandPalette)
    }

    @Test func commandKChangesMeaningFromPlainK() {
        // The palette must not be reachable by accident while navigating.
        #expect(action([KeyInput(.character("k"))]) == .moveSelectionUp)
        #expect(action([KeyInput(.character("k"), [.command])]) == .openCommandPalette)
    }

    @Test func prefixKeyAloneProducesNoActionAndGoesPending() {
        var engine = engine()
        #expect(engine.handle(KeyInput(.character("g"))) == .pending)
        #expect(engine.isAwaitingChord)
    }

    @Test func goToInboxRequiresBothKeysOfTheChord() {
        #expect(action([KeyInput(.character("g")), KeyInput(.character("i"))]) == .goToInbox)
        #expect(action([KeyInput(.character("i"))]) == nil)
    }

    @Test func unboundKeyAfterAPrefixIsSwallowedAndResets() {
        var engine = engine()
        _ = engine.handle(KeyInput(.character("g")))

        // "g" then "j" must not fall through and scroll the list.
        #expect(engine.handle(KeyInput(.character("j"))) == .unhandled)
        #expect(!engine.isAwaitingChord)

        // Back to ready: "j" alone works again.
        #expect(engine.handle(KeyInput(.character("j"))) == .action(.moveSelectionDown))
    }

    @Test func escapeAfterAPrefixCancelsTheChordWithoutGoingBack() {
        var engine = engine()
        _ = engine.handle(KeyInput(.character("g")))

        // Escaping a half-typed chord cancels the chord, not the view.
        #expect(engine.handle(KeyInput(.escape)) == .pending)
        #expect(!engine.isAwaitingChord)
    }

    @Test func escapeWhenNothingIsPendingReportsBack() {
        var engine = engine()
        #expect(engine.handle(KeyInput(.escape)) == .action(.back))
    }

    @Test func unboundKeyIsUnhandled() {
        var engine = engine()
        #expect(engine.handle(KeyInput(.character("z"))) == .unhandled)
    }

    @Test func uppercaseBindingsResolve() {
        #expect(action([KeyInput(.character("E"))]) == .archiveSelected)
        #expect(action([KeyInput(.character("G")), KeyInput(.character("I"))]) == .goToInbox)
    }

    @Test func aChordIsNotConfusedWithAModifiedKey() {
        // Cmd+g is not the chord prefix.
        var engine = engine()
        #expect(engine.handle(KeyInput(.character("g"), [.command])) == .unhandled)
        #expect(!engine.isAwaitingChord)
    }
}
