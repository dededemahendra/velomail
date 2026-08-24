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

    // MARK: - The v1 keymap

    private struct Chord: Hashable {
        let prefix: KeyInput
        let second: KeyInput
    }

    private static let bindings: [KeyInput: MailAction] = [
        KeyInput(.character("j")): .moveSelectionDown,
        KeyInput(.character("k")): .moveSelectionUp,
        KeyInput(.character("o")): .openSelected,
        KeyInput(.enter): .openSelected,
        KeyInput(.character("e")): .archiveSelected,
        KeyInput(.character("r")): .reply,
        KeyInput(.character("c")): .compose,
        KeyInput(.character("s")): .summarizeThread,
        KeyInput(.character("d")): .suggestReplies,
        KeyInput(.escape): .back,
        KeyInput(.enter, [.command]): .send,
        KeyInput(.character("k"), [.command]): .openCommandPalette,
        KeyInput(.character("/")): .openSearch,
        KeyInput(.character("f"), [.command]): .openSearch,
    ]

    private static let chords: [Chord: MailAction] = [
        Chord(prefix: KeyInput(.character("g")), second: KeyInput(.character("i"))): .goToInbox,
    ]

    /// Unmodified `g` only — `Cmd+g` is a different keystroke and not a prefix.
    private static let chordPrefixes: Set<KeyInput> = [KeyInput(.character("g"))]
}
