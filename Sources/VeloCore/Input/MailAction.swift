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
    case trashSelected
    case markUnreadSelected
    case reply
    case replyAll
    case forward
    case send
    case compose
    case goToInbox
    case goToSent
    case goToSnoozed
    case goToDrafts
    case goToStarred
    case goToArchive
    case loadOlderMail
    /// Ask for a sync pass now instead of waiting out the backoff.
    case syncNow
    /// Mark every row in the list, so one keystroke stands in for forty.
    case selectAll
    /// Clear the unread state of everything in the list at once.
    case markAllRead
    /// Send the selected thread to Gmail's spam folder.
    case reportSpam
    /// Open the selected thread in Gmail on the web, for whatever this client
    /// cannot do.
    case openInGmail
    /// Write the selected thread out as a text file.
    case exportThread
    /// Show the whole keymap on one card.
    case showShortcuts
    /// Show who is filling the inbox.
    case showSenders
    /// Which label is on the `Command`, not the action: there is one per
    /// account and they are renamed and deleted, so a case each is not on the
    /// cards and a raw-valued enum cannot carry one anyway.
    case goToLabel
    case fileInLabel
    case unfileFromLabel
    case switchAccount
    case addAccount
    case openSettings
    case snoozeAtTime
    case sendAtTime
    case sendTomorrow
    case sendNextWeek
    case snoozeUntilTomorrow
    case snoozeUntilNextWeek
    case unsnoozeSelected
    case toggleRemoteImages
    /// Leave the current view; also cancels a half-typed chord.
    case back
    case openCommandPalette
    case openSearch
    case snoozeSelected
    case undo
    case showFollowUps
    case toggleFocus
    case discardDraft
    case showAnalytics
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
    case draftReplyWithAI
    case triageThread

    /// True for actions that need an LLM provider.
    public var isAI: Bool {
        switch self {
        // draftReplyWithAI belongs here too. Left out, it stayed in the
        // palette with no provider configured and did nothing when run.
        case .summarizeThread, .suggestReplies, .triageThread, .draftReplyWithAI: return true
        default: return false
        }
    }

    /// Actions that mean nothing without a `Command.argument` to go with them.
    ///
    /// They are absent from the fixed registry on purpose: there is one per
    /// label, and which labels exist is a question about the account rather
    /// than about the app.
    public static let needingAnArgument: Set<MailAction> = [.goToLabel, .fileInLabel, .unfileFromLabel, .switchAccount]
}
