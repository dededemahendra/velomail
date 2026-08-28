import Foundation
import VeloCore

/// What an empty list should say for itself.
///
/// Whether a list is empty and *why* it is empty are different questions, and
/// the app was only asking the first. A fresh install and a morning of
/// finished triage produce the same empty table, so mail that had not arrived
/// yet was announced as "Inbox zero" under a green tick.
struct EmptyState: Equatable {
    let symbol: String
    let headline: String
    let detail: String
    /// True while mail is actively on its way, so the view can spin instead of
    /// drawing a symbol. Not a spinner *and* a symbol: a turning spinner above
    /// a download arrow is one fact stated twice.
    let isWaiting: Bool
    /// What a button here should say, or nothing when pressing one would
    /// achieve nothing. Offering "Try again" over a sync that is already
    /// running invites the reader to press it and watch nothing change.
    let retry: String?

    static func of(scope: MailScope, status: SyncStatus, hasSeenMail: Bool) -> EmptyState {
        // Once mail has arrived, an empty list is a fact about the list, and a
        // sync that is failing right now does not change what is in it.
        guard !hasSeenMail else { return settled(scope) }

        switch status {
        case .idle, .syncing:
            return EmptyState(symbol: "arrow.down.circle",
                              headline: "Fetching your mail",
                              detail: "The first sync takes a moment.",
                              isWaiting: true, retry: nil)
        case .offline:
            // Not spinning: the status bar below already counts the retries,
            // and a spinner over a struck-through aerial contradicts itself.
            return EmptyState(symbol: "wifi.slash",
                              headline: "Cannot reach Gmail",
                              detail: "Your mail will appear once the connection is back.",
                              isWaiting: false, retry: "Try again")
        case .expired:
            return EmptyState(symbol: "person.crop.circle.badge.exclamationmark",
                              headline: "Sign-in expired",
                              detail: "Gmail needs you to sign in again.",
                              isWaiting: false, retry: "Sign in")
        case let .failed(reason):
            return EmptyState(symbol: "exclamationmark.triangle",
                              headline: "Sync could not finish",
                              detail: reason, isWaiting: false, retry: "Try again")
        case .upToDate:
            // Synced, and there was genuinely nothing to bring down.
            return settled(scope)
        }
    }

    private static func settled(_ scope: MailScope) -> EmptyState {
        switch scope {
        case .inbox:
            return EmptyState(symbol: "checkmark.circle", headline: "Inbox zero",
                              detail: "Nothing left to triage.", isWaiting: false, retry: nil)
        case .sent:
            return EmptyState(symbol: "paperplane", headline: "Nothing sent yet",
                              detail: "Messages you send appear here.", isWaiting: false, retry: nil)
        case .snoozed:
            return EmptyState(symbol: "clock", headline: "Nothing snoozed",
                              detail: "Threads you put off come back here.", isWaiting: false, retry: nil)
        case .starred:
            return EmptyState(symbol: "star", headline: "Nothing starred",
                              detail: "Press s on a thread to keep it to hand.", isWaiting: false, retry: nil)
        case .archive:
            return EmptyState(symbol: "archivebox", headline: "Nothing filed away",
                              detail: "Threads you archive with e wait here.", isWaiting: false, retry: nil)
        case let .label(_, name):
            return EmptyState(symbol: "tag", headline: "Nothing in \(name)",
                              detail: "File a thread here from the command palette.",
                              isWaiting: false, retry: nil)
        }
    }
}
