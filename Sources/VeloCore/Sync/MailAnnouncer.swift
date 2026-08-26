import Foundation

/// Decides what new mail deserves a notification.
///
/// Showing a banner is trivial; choosing what to show is where this goes wrong,
/// and every failure mode is the same shape — telling the user something they
/// did not need to hear. Kept pure and headless so those decisions are testable
/// without a notification centre.
public struct MailAnnouncer: Sendable {
    /// One banner's worth.
    public struct Announcement: Equatable, Sendable {
        public let title: String
        public let subtitle: String
        public let threadID: String
    }

    public struct Result: Equatable, Sendable {
        public let items: [Announcement]
        /// How many more arrived than could be shown.
        public let additionalCount: Int
        /// The newest date accounted for; persist this and pass it back next time.
        public let highWaterMark: Date?
    }

    /// Twelve messages arriving at once is one summary, not twelve
    /// interruptions.
    public static let maximumBanners = 3

    public init() {}

    /// - Parameter since: the mark from the previous run. `nil` means this
    ///   installation has never announced anything, which is treated as "say
    ///   nothing, just record where we are" — otherwise a first backfill fires
    ///   a banner per message.
    public func announce(messages: [Message], identity: String, since: Date?) -> Result {
        let newest = messages.map(\.date).max()

        guard let since else {
            return Result(items: [], additionalCount: 0, highWaterMark: newest)
        }

        let mine = Draft.normalizedAddress(identity)
        let candidates = messages
            .filter { $0.date > since }
            .filter { $0.isUnread }
            .filter { $0.labelIDs.contains("INBOX") }
            // Sending puts a message in the thread; it must not come back as
            // "new mail from you".
            .filter { Draft.normalizedAddress($0.sender) != mine }
            .sorted { $0.date > $1.date }

        let shown = candidates.prefix(Self.maximumBanners).map {
            Announcement(title: displayName(of: $0.sender),
                         subtitle: $0.subject.isEmpty ? "(no subject)" : $0.subject,
                         threadID: $0.threadID)
        }

        // The mark never goes backwards, so an empty sync cannot un-announce
        // anything already shown.
        let mark = [since, newest].compactMap { $0 }.max()

        return Result(items: Array(shown),
                      additionalCount: max(0, candidates.count - shown.count),
                      highWaterMark: mark)
    }

    private func displayName(of sender: String) -> String {
        let name = MailAnnouncer.name(in: sender)
        return name.isEmpty ? sender : name
    }

    /// "Alice <a@b.com>" reads as "Alice"; a bare address stays as it is.
    static func name(in sender: String) -> String {
        guard let open = sender.firstIndex(of: "<") else { return sender }
        return String(sender[sender.startIndex..<open]).trimmingCharacters(in: .whitespaces)
    }
}
