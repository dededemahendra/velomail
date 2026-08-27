import Foundation

/// One entry in the `Cmd+K` palette.
public struct Command: Equatable, Sendable {
    public let title: String
    public let action: MailAction
    /// What the action is about, when it needs telling. A label id, today.
    public let argument: String?

    public init(title: String, action: MailAction, argument: String? = nil) {
        self.title = title
        self.action = action
        self.argument = argument
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
        Command(title: "Archive", action: .archiveSelected),
        Command(title: "Delete", action: .trashSelected),
        Command(title: "Mark Unread", action: .markUnreadSelected),
        Command(title: "Reply", action: .reply),
        Command(title: "Reply All", action: .replyAll),
        Command(title: "Forward", action: .forward),
        Command(title: "Compose", action: .compose),
        Command(title: "Send", action: .send),
        Command(title: "Open", action: .openSelected),
        Command(title: "Go to Inbox", action: .goToInbox),
        Command(title: "Next Thread", action: .moveSelectionDown),
        Command(title: "Previous Thread", action: .moveSelectionUp),
        Command(title: "Back", action: .back),
        Command(title: "Command Palette", action: .openCommandPalette),
        Command(title: "Search", action: .openSearch),
        Command(title: "Star", action: .toggleStar),
        Command(title: "Select", action: .toggleMark),
        Command(title: "Snooze", action: .snoozeSelected),
        Command(title: "Go to Sent", action: .goToSent),
        Command(title: "Go to Snoozed", action: .goToSnoozed),
        Command(title: "Go to Drafts", action: .goToDrafts),
        Command(title: "Go to Starred", action: .goToStarred),
        Command(title: "Go to Archive", action: .goToArchive),
        Command(title: "Load older mail", action: .loadOlderMail),
        Command(title: "Add another account", action: .addAccount),
        Command(title: "Settings", action: .openSettings),
        Command(title: "Send tomorrow morning", action: .sendTomorrow),
        Command(title: "Send next week", action: .sendNextWeek),
        Command(title: "Snooze until tomorrow", action: .snoozeUntilTomorrow),
        Command(title: "Snooze until next week", action: .snoozeUntilNextWeek),
        Command(title: "Unsnooze", action: .unsnoozeSelected),
        Command(title: "Toggle remote images", action: .toggleRemoteImages),
        Command(title: "Undo", action: .undo),
        Command(title: "Awaiting Reply", action: .showFollowUps),
        Command(title: "Focus Mode", action: .toggleFocus),
        Command(title: "Discard Draft", action: .discardDraft),
        Command(title: "Analytics", action: .showAnalytics),
        Command(title: "Unsubscribe", action: .unsubscribe),
        Command(title: "Summarise Thread", action: .summarizeThread),
        Command(title: "Suggest Replies", action: .suggestReplies),
        Command(title: "Write a Reply", action: .draftReplyWithAI),
        Command(title: "Triage Thread", action: .triageThread),
    ])

    /// Commands matching `query`, best first. An empty query is everything, in
    /// registration order.
    ///
    /// Ranking is prefix-first, then earliest match, then shortest title — so
    /// the obvious command leads rather than whichever was registered first,
    /// and the order is deterministic enough to assert.
    public func matches(_ query: String) -> [Command] {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return commands }

        return commands
            .compactMap { command -> (command: Command, rank: Rank)? in
                guard let start = Self.subsequenceStart(of: needle, in: command.title.lowercased())
                else { return nil }
                return (command, Rank(isPrefix: start == 0, start: start, length: command.title.count))
            }
            .sorted { $0.rank < $1.rank }
            .map(\.command)
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
