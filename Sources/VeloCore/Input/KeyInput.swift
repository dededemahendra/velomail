import Foundation

/// One keystroke, deliberately free of AppKit so the engine is testable without
/// a window. Translating an `NSEvent` into this is the app layer's job.
public struct KeyInput: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case character(Character)
        case enter
        case escape
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        // Fold case at construction so a binding on "j" still fires with caps
        // lock on, and so equality and hashing agree without special cases.
        switch key {
        case let .character(character):
            self.key = .character(Character(character.lowercased()))
        default:
            self.key = key
        }
        self.modifiers = modifiers
    }
}
