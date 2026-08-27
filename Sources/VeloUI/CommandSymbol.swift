import Foundation
import VeloCore

/// The icon a command wears in the palette.
///
/// A presentation concern rather than something `MailAction` should carry:
/// the engine has no opinion about SF Symbols, and giving it one would put
/// AppKit vocabulary in a type that is otherwise pure.
enum CommandSymbol {
    static func name(for action: MailAction) -> String {
        switch action {
        // Moving around
        case .goToInbox: return "tray"
        case .goToSent: return "paperplane"
        case .goToSnoozed: return "clock"
        case .goToDrafts: return "square.and.pencil"
        case .goToStarred: return "star"
        case .goToArchive: return "archivebox"
        case .showFollowUps: return "clock.arrow.circlepath"
        case .showAnalytics: return "chart.bar"
        case .openSearch: return "magnifyingglass"
        case .openCommandPalette: return "command"
        case .back: return "chevron.left"
        case .moveSelectionUp: return "chevron.up"
        case .moveSelectionDown: return "chevron.down"
        case .openSelected: return "envelope.open"

        // Doing something to mail
        case .archiveSelected: return "archivebox"
        case .trashSelected: return "trash"
        case .markUnreadSelected: return "envelope.badge"
        case .toggleStar: return "star.fill"
        case .toggleMark: return "checkmark.circle"
        case .snoozeSelected, .snoozeUntilTomorrow, .snoozeUntilNextWeek: return "clock.badge"
        case .unsnoozeSelected: return "clock.badge.xmark"
        case .unsubscribe: return "hand.raised"
        case .loadOlderMail: return "arrow.down.circle"
        case .syncNow: return "arrow.clockwise"
        case .selectAll: return "checklist"
        case .markAllRead: return "envelope.open"
        case .reportSpam: return "exclamationmark.octagon"
        case .openInGmail: return "safari"
        case .exportThread: return "square.and.arrow.down"
        case .showShortcuts: return "keyboard"
        case .showSenders: return "person.2"
        case .goToLabel: return "tag"
        case .switchAccount: return "person.crop.circle"
        case .addAccount: return "person.badge.plus"
        case .openSettings: return "gearshape"
        case .snoozeAtTime: return "calendar.badge.clock"
        case .sendAtTime: return "calendar"
        case .fileInLabel: return "tag.fill"
        case .unfileFromLabel: return "tag.slash"

        // Writing
        case .compose: return "square.and.pencil"
        case .reply: return "arrowshape.turn.up.left"
        case .replyAll: return "arrowshape.turn.up.left.2"
        case .forward: return "arrowshape.turn.up.right"
        case .send: return "paperplane.fill"
        case .sendTomorrow, .sendNextWeek: return "paperplane.circle"
        case .discardDraft: return "trash.slash"

        // Undo, settings, AI
        case .undo: return "arrow.uturn.backward"
        case .toggleFocus: return "moon"
        case .toggleRemoteImages: return "photo"
        case .summarizeThread: return "text.alignleft"
        case .suggestReplies: return "bubble.left.and.bubble.right"
        case .draftReplyWithAI: return "wand.and.stars"
        case .triageThread: return "tray.2"
        }
    }
}
