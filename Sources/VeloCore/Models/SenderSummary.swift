import Foundation

/// One correspondent, and how much of your mailbox is theirs.
///
/// A mailbox is not a flat list of messages, it is a handful of senders sending
/// a great deal and a long tail sending once. Nothing in this app would tell
/// you which, so triage had to be done a thread at a time even when four
/// hundred of them came from the same address.
public struct SenderSummary: Equatable, Sendable, Identifiable {
    /// Lowercased bare address, which is what a rule matches on.
    public let address: String
    /// The best name seen for them, or the address when they never gave one.
    public let name: String
    public let threads: Int
    public let unread: Int
    /// True when at least one of their messages says how to leave the list.
    public let canUnsubscribe: Bool
    public let newest: Date

    public var id: String { address }

    public init(address: String, name: String, threads: Int, unread: Int,
                canUnsubscribe: Bool, newest: Date) {
        self.address = address
        self.name = name
        self.threads = threads
        self.unread = unread
        self.canUnsubscribe = canUnsubscribe
        self.newest = newest
    }

    /// What to show: the name when there is one, the address otherwise.
    public var displayName: String { name.isEmpty ? address : name }

    /// This sender's share of a mailbox of `total` threads, 0...1.
    public func share(of total: Int) -> Double {
        total > 0 ? Double(threads) / Double(total) : 0
    }
}

public extension MailRule {
    /// "Everything from this address, from now on."
    ///
    /// Matched on the bare address rather than the friendly name, because bulk
    /// senders change the name on every send and never the address.
    static func forSender(_ summary: SenderSummary, doing actions: [RuleAction],
                          named name: String, order: Int) -> MailRule {
        MailRule(id: "sender-\(summary.address)-\(actions.map(\.rawValue).joined(separator: "-"))",
                 name: name, order: order,
                 conditions: [.senderContains(summary.address)],
                 actions: actions)
    }
}

/// Turns raw sender headers into one row per correspondent.
///
/// Pure, so the grouping rules are testable without a database: the address is
/// the identity, and the richest name wins because one bare "noreply@x.com"
/// must not erase a full name seen on the message before it.
public enum SenderRollup {
    /// One row per address, busiest first, then most recent, then by address so
    /// the order never wobbles between two senders of equal weight.
    public static func summarise(_ rows: [Row]) -> [SenderSummary] {
        var seen: [String: SenderSummary] = [:]
        for row in rows {
            let address = Draft.normalizedAddress(row.sender)
            guard address.contains("@") else { continue }
            let name = Self.name(in: row.sender) ?? ""
            if let existing = seen[address] {
                seen[address] = SenderSummary(
                    address: address,
                    // The richest name wins, not the newest: bulk senders vary
                    // the friendly name and a bare address must not win.
                    name: name.count > existing.name.count ? name : existing.name,
                    threads: existing.threads + 1,
                    unread: existing.unread + (row.isUnread ? 1 : 0),
                    canUnsubscribe: existing.canUnsubscribe || row.canUnsubscribe,
                    newest: max(existing.newest, row.date))
            } else {
                seen[address] = SenderSummary(address: address, name: name, threads: 1,
                                              unread: row.isUnread ? 1 : 0,
                                              canUnsubscribe: row.canUnsubscribe,
                                              newest: row.date)
            }
        }
        return seen.values.sorted {
            if $0.threads != $1.threads { return $0.threads > $1.threads }
            if $0.newest != $1.newest { return $0.newest > $1.newest }
            return $0.address < $1.address
        }
    }

    /// One thread's worth of what the rollup needs.
    public struct Row: Equatable, Sendable {
        public let sender: String
        public let isUnread: Bool
        public let canUnsubscribe: Bool
        public let date: Date

        public init(sender: String, isUnread: Bool, canUnsubscribe: Bool, date: Date) {
            self.sender = sender
            self.isUnread = isUnread
            self.canUnsubscribe = canUnsubscribe
            self.date = date
        }
    }

    private static func name(in header: String) -> String? {
        guard let open = header.firstIndex(of: "<") else { return nil }
        let name = header[header.startIndex..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
