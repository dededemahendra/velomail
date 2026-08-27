import Foundation

/// Maps keystrokes to `MailAction`s, including multi-key chords like `g i`.
///
/// A two-state machine rather than a special case for `g`: the moment a second
/// chord (`g s`, `g t`) is added, a special case becomes a bug, and the state
/// machine already handles it.
public struct KeyboardEngine {
    public enum Outcome: Equatable, Sendable {
        case action(MailAction)
        /// The keystroke was consumed but means nothing on its own — either a
        /// chord prefix, or the escape that cancelled one.
        case pending
        case unhandled
    }

    private enum State: Equatable {
        case ready
        case awaitingChord(prefix: KeyInput)
    }

    private var state: State = .ready

    public init() {}

    /// True while a chord prefix has been typed and its second key is awaited.
    public var isAwaitingChord: Bool {
        if case .awaitingChord = state { return true }
        return false
    }

    public mutating func handle(_ input: KeyInput) -> Outcome {
        switch state {
        case let .awaitingChord(prefix):
            state = .ready
            // Escape cancels the half-typed chord. It must not also fire
            // `.back`, or cancelling a chord would leave the view as well.
            if input.key == .escape { return .pending }
            if let action = Self.chords[Chord(prefix: prefix, second: input)] {
                return .action(action)
            }
            // Swallowed on purpose: after `g`, a `j` is a mistyped chord, not a
            // request to scroll the list.
            return .unhandled

        case .ready:
            if Self.chordPrefixes.contains(input) {
                state = .awaitingChord(prefix: input)
                return .pending
            }
            if let action = Self.bindings[input] { return .action(action) }
            return .unhandled
        }
    }

    /// How to reach `action` from the keyboard, or nil when nothing does.
    ///
    /// Derived from the keymap rather than written alongside it, so a binding
    /// and the hint that advertises it cannot drift apart -- and a new binding
    /// becomes discoverable in the palette with no extra step.
    public static func shortcutLabel(for action: MailAction) -> String? {
        if let chord = chords.first(where: { $0.value == action })?.key {
            return "\(label(for: chord.prefix)) \(label(for: chord.second))"
        }
        // Prefer the shortest label when several keys do the same thing, so
        // "E" wins over a chord and a bare key wins over a modified one.
        return bindings
            .filter { $0.value == action }
            .map { label(for: $0.key) }
            .min { ($0.count, $0) < ($1.count, $1) }
    }

    private static func label(for input: KeyInput) -> String {
        var text = ""
        if input.modifiers.contains(.command) { text += "⌘" }
        if input.modifiers.contains(.shift) { text += "⇧" }

        switch input.key {
        case let .character(character):
            text += String(character).uppercased()
        case .enter:
            text += "↩"
        case .escape:
            // Spelled out: the ⎋ glyph is unrecognisable to most people.
            text += "esc"
        case .delete:
            text += "⌫"
        }
        return text
    }

    // MARK: - The v1 keymap

    struct Chord: Hashable {
        let prefix: KeyInput
        let second: KeyInput
    }

    /// Every character the keymap listens for, chord prefixes and second keys
    /// included.
    ///
    /// Exposed so the event monitor can allow exactly these through rather than
    /// keeping a hand-written list beside them. A binding on punctuation that
    /// the monitor filtered out was silently unreachable: `Cmd+,` for settings
    /// was added, shipped, and did nothing at all.
    public static var boundCharacters: Set<Character> {
        var found: Set<Character> = []
        for input in bindings.keys {
            if case let .character(character) = input.key { found.insert(character) }
        }
        for chord in chords.keys {
            if case let .character(character) = chord.prefix.key { found.insert(character) }
            if case let .character(character) = chord.second.key { found.insert(character) }
        }
        return found
    }

    private static let bindings: [KeyInput: MailAction] = [
        KeyInput(.character("j")): .moveSelectionDown,
        KeyInput(.character("k")): .moveSelectionUp,
        KeyInput(.character("o")): .openSelected,
        KeyInput(.enter): .openSelected,
        KeyInput(.character("e")): .archiveSelected,
        KeyInput(.character("r")): .reply,
        KeyInput(.character("r"), [.shift]): .replyAll,
        KeyInput(.character("f")): .forward,
        KeyInput(.character("c")): .compose,
        KeyInput(.character("s")): .toggleStar,
        KeyInput(.character("x")): .toggleMark,
        KeyInput(.character("h")): .snoozeSelected,
        KeyInput(.character("u")): .unsubscribe,
        KeyInput(.character("u"), [.shift]): .markUnreadSelected,
        KeyInput(.delete): .trashSelected,
        KeyInput(.character("z"), [.command]): .undo,
        KeyInput(.escape): .back,
        KeyInput(.enter, [.command]): .send,
        KeyInput(.character("k"), [.command]): .openCommandPalette,
        KeyInput(.character(","), [.command]): .openSettings,
        KeyInput(.character("/")): .openSearch,
        KeyInput(.character("f"), [.command]): .openSearch,
    ]

    private static let chords: [Chord: MailAction] = [
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("i"))): .goToInbox,
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("s"))): .goToSent,
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("h"))): .goToSnoozed,
        // `t` for starred and `e` for archive, matching the keys that *do*
        // those things: `s` stars and `e` archives, and `g s` was already Sent.
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("t"))): .goToStarred,
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("e"))): .goToArchive,
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("f"))): .showFollowUps,
        // `g d` is drafts in every other mail client; focus mode is ours to
        // place, so it moved to `g z` rather than holding the conventional key.
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("d"))): .goToDrafts,
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("z"))): .toggleFocus,
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("a"))): .showAnalytics,
        // AI lives behind `a`, freeing `s` for star. AI is optional and off by
        // default, so on most launches `s` and `d` were two of the best keys on
        // the keyboard doing nothing at all; star works for every user, always.
        Chord(prefix: KeyInput(.character("a")), second: KeyInput(.character("s"))): .summarizeThread,
        Chord(prefix: KeyInput(.character("a")), second: KeyInput(.character("r"))): .suggestReplies,
        Chord(prefix: KeyInput(.character("a")), second: KeyInput(.character("t"))): .triageThread,
        Chord(prefix: KeyInput(.character("a")), second: KeyInput(.character("d"))): .draftReplyWithAI,
    ]

    /// Unmodified `g` and `a` only — `Cmd+g` and `Cmd+A` (select-all in a text
    /// field) are different keystrokes and must not open a chord.
    private static let chordPrefixes: Set<KeyInput> = [
        KeyInput(.character("g")),
        KeyInput(.character("a")),
    ]
}
