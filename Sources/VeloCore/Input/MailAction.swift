import Foundation

/// Everything the v1 keymap can ask for. The engine decides *what* was asked;
/// performing it against `OutboundService`/`MailStore` is the view model's job,
/// which is what keeps this whole layer testable without a window.
public enum MailAction: String, Equatable, Sendable, CaseIterable {
    case moveSelectionDown
    case moveSelectionUp
    case openSelected
    /// Archive and auto-advance — the core triage gesture.
    case archiveSelected
    case reply
    case send
    case compose
    case goToInbox
    /// Leave the current view; also cancels a half-typed chord.
    case back
    case openCommandPalette
    case openSearch
    case snoozeSelected
    case undoSend
    case showFollowUps
    case toggleFocus
    /// Star or unstar the selection. A star is a real Gmail label, so it is the
    /// one triage gesture that works on every launch for every user.
    case toggleStar
    /// Mark or unmark the row, widening what the next action applies to.
    case toggleMark
    /// Act on the sender's own `List-Unsubscribe` instruction.
    case unsubscribe

    // AI. Present only when a provider is configured -- an action that is
    // visible and always errors is worse than one that is not offered.
    case summarizeThread
    case suggestReplies
    case triageThread

    /// True for actions that need an LLM provider.
    public var isAI: Bool {
        switch self {
        case .summarizeThread, .suggestReplies, .triageThread: return true
        default: return false
        }
    }
}
