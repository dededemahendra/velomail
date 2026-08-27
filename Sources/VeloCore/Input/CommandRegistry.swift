import Foundation

/// Where a command sits when the palette is being browsed rather than typed at.
///
/// Fifty commands in one flat column is a list nobody reads to the end of.
/// The order is how someone would go looking: what to do with what is in front
/// of you, then writing, then going elsewhere, then the mailbox as a whole.
public enum CommandGroup: String, CaseIterable, Equatable, Sendable {
    case triage = "Triage"
    case write = "Write"
    case navigate = "Go"
    case mailbox = "Mailbox"
    case assistant = "Assistant"
    case app = "App"
}

/// One entry in the `Cmd+K` palette.
public struct Command: Equatable, Sendable {
    public let title: String
    public let action: MailAction
    /// What the action is about, when it needs telling. A label id, today.
    public let argument: String?
    public let group: CommandGroup

    public init(title: String, action: MailAction, argument: String? = nil,
                group: CommandGroup = .mailbox) {
        self.title = title
        self.action = action
        self.argument = argument
        self.group = group
    }
}

/// The command palette's catalogue and its matching.
///
/// Subsequence matching (letters in order, gaps allowed) is what every palette
/// does, so `arc` finds "Archive" and `gti` finds "Go to Inbox" without the user
/// knowing the exact wording.
public struct CommandRegistry: Equatable, Sendable {
    public let commands: [Command]

    public init(commands: [Command]) {
        self.commands = commands
    }

    /// Every v1 action, so the palette is a complete discoverability net for the
    /// keymap and nothing is keyboard-only.
    public static let v1 = CommandRegistry(commands: [
        Command(title: "Archive", action: .archiveSelected, group: .triage),
        Command(title: "Delete", action: .trashSelected, group: .triage),
        Command(title: "Mark Unread", action: .markUnreadSelected, group: .triage),
        Command(title: "Reply", action: .reply, group: .write),
        Command(title: "Reply All", action: .replyAll, group: .write),
        Command(title: "Forward", action: .forward, group: .write),
        Command(title: "Compose", action: .compose, group: .write),
        Command(title: "Send", action: .send, group: .write),
        Command(title: "Open", action: .openSelected, group: .navigate),
        Command(title: "Go to Inbox", action: .goToInbox, group: .navigate),
        Command(title: "Next Thread", action: .moveSelectionDown, group: .navigate),
        Command(title: "Previous Thread", action: .moveSelectionUp, group: .navigate),
        Command(title: "Back", action: .back, group: .navigate),
        Command(title: "Command Palette", action: .openCommandPalette, group: .navigate),
        Command(title: "Search", action: .openSearch, group: .navigate),
        Command(title: "Star", action: .toggleStar, group: .triage),
        Command(title: "Select", action: .toggleMark, group: .triage),
        Command(title: "Snooze", action: .snoozeSelected, group: .triage),
        Command(title: "Go to Sent", action: .goToSent, group: .navigate),
        Command(title: "Go to Snoozed", action: .goToSnoozed, group: .navigate),
        Command(title: "Go to Drafts", action: .goToDrafts, group: .navigate),
        Command(title: "Go to Starred", action: .goToStarred, group: .navigate),
        Command(title: "Go to Archive", action: .goToArchive, group: .navigate),
        Command(title: "Load older mail", action: .loadOlderMail, group: .mailbox),
        Command(title: "Sync now", action: .syncNow, group: .mailbox),
        Command(title: "Select all", action: .selectAll, group: .triage),
        Command(title: "Mark all as read", action: .markAllRead, group: .triage),
        Command(title: "Report spam", action: .reportSpam, group: .triage),
        Command(title: "Open in Gmail", action: .openInGmail, group: .mailbox),
        Command(title: "Export thread", action: .exportThread, group: .mailbox),
        Command(title: "Add another account", action: .addAccount, group: .app),
        Command(title: "Settings", action: .openSettings, group: .app),
        Command(title: "Send tomorrow morning", action: .sendTomorrow, group: .write),
        Command(title: "Send next week", action: .sendNextWeek, group: .write),
        Command(title: "Send at\u{2026}", action: .sendAtTime, group: .write),
        Command(title: "Snooze until tomorrow", action: .snoozeUntilTomorrow, group: .triage),
        Command(title: "Snooze until next week", action: .snoozeUntilNextWeek, group: .triage),
        Command(title: "Snooze until\u{2026}", action: .snoozeAtTime, group: .triage),
        Command(title: "Unsnooze", action: .unsnoozeSelected, group: .triage),
        Command(title: "Toggle remote images", action: .toggleRemoteImages, group: .mailbox),
        Command(title: "Undo", action: .undo, group: .triage),
        Command(title: "Awaiting Reply", action: .showFollowUps, group: .navigate),
        Command(title: "Focus Mode", action: .toggleFocus, group: .app),
        Command(title: "Discard Draft", action: .discardDraft, group: .write),
        Command(title: "Analytics", action: .showAnalytics, group: .mailbox),
        Command(title: "Unsubscribe", action: .unsubscribe, group: .triage),
        Command(title: "Summarise Thread", action: .summarizeThread, group: .assistant),
        Command(title: "Suggest Replies", action: .suggestReplies, group: .assistant),
        Command(title: "Write a Reply", action: .draftReplyWithAI, group: .assistant),
        Command(title: "Triage Thread", action: .triageThread, group: .assistant),
    ])

    /// Commands matching `query`, best first. An empty query is everything, in
    /// registration order.
    ///
    /// Ranking is prefix-first, then earliest match, then shortest title — so
    /// the obvious command leads rather than whichever was registered first,
    /// and the order is deterministic enough to assert.
    public func matches(_ query: String, recents: [MailAction] = []) -> [Command] {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return browsing(recents: recents) }

        return commands
            .compactMap { command -> (command: Command, rank: Rank)? in
                guard let start = Self.subsequenceStart(of: needle, in: command.title.lowercased())
                else { return nil }
                return (command, Rank(isPrefix: start == 0, start: start, length: command.title.count))
            }
            .sorted { $0.rank < $1.rank }
            .map(\.command)
    }

    /// The whole catalogue with the commands just used at the front.
    ///
    /// Recency only applies to an empty query. Someone who has typed something
    /// knows what they are after, and reordering their results by what they did
    /// yesterday would move the answer out from under them.
    private func browsing(recents: [MailAction]) -> [Command] {
        guard !recents.isEmpty else { return grouped(commands) }
        var used: [Command] = []
        for action in recents {
            // First match only: two commands can share an action (a labelled
            // one and a bare one) and listing both under Recent reads as a bug.
            if let command = commands.first(where: { $0.action == action && $0.argument == nil }) {
                used.append(command)
            }
        }
        let usedActions = Set(used.map(\.action))
        return used + grouped(commands.filter { !usedActions.contains($0.action) })
    }

    /// The catalogue in group order, stable within each group.
    ///
    /// Registration order alone left commands of one group scattered down the
    /// list, so a heading covered whatever happened to follow it rather than
    /// the group it named.
    private func grouped(_ commands: [Command]) -> [Command] {
        CommandGroup.allCases.flatMap { group in
            commands.filter { $0.group == group }
        }
    }

    /// How many recent commands are worth floating. Beyond a handful the top of
    /// the list stops being a shortcut and becomes a second catalogue.
    public static let recentLimit = 4

    /// `used` put at the front of `previous`, capped, with no repeats.
    public static func remember(_ used: MailAction, in previous: [MailAction]) -> [MailAction] {
        ([used] + previous.filter { $0 != used }).prefix(recentLimit).map { $0 }
    }

    // MARK: - Internals

    private struct Rank: Comparable {
        let isPrefix: Bool
        let start: Int
        let length: Int

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.length < rhs.length
        }
    }

    /// Index of the first matched character if every character of `needle`
    /// appears in `haystack` in order, else nil. Spaces in the haystack are
    /// skippable like any other gap, so "gti" spans "Go to Inbox".
    private static func subsequenceStart(of needle: String, in haystack: String) -> Int? {
        var first: Int?
        let characters = Array(needle)
        var next = 0
        for (offset, character) in haystack.enumerated() where next < characters.count {
            if character == characters[next] {
                if first == nil { first = offset }
                next += 1
            }
        }
        return next == characters.count ? first : nil
    }
}
