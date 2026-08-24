import Foundation
import GRDB

/// Threads where you spoke last and nobody answered.
///
/// Derived from what is already stored rather than flagged on a column, which
/// means it self-corrects: the moment a reply arrives the thread stops
/// appearing, with nothing having to notice and clear a flag. It also means no
/// background job and no state that can go stale.
public struct FollowUpService: Sendable {
    private let store: MailStore

    public init(_ store: MailStore) {
        self.store = store
    }

    /// Threads whose newest message is yours and older than `after`.
    /// - Returns: the stalest first, so the most overdue is chased first.
    public func awaitingReply(identity: String, after window: TimeInterval,
                              now: Date = Date()) throws -> [MailThread] {
        let cutoff = now.addingTimeInterval(-window)
        let mine = Draft.normalizedAddress(identity)

        // The newest sender is fetched in the same query rather than looked up
        // per thread: a store call inside a read block re-enters the database
        // connection, which GRDB traps on.
        let candidates: [(thread: MailThread, newestSender: String)] =
            try store.database.dbQueue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT thread.*, message.sender AS newestSender FROM thread
                    JOIN message ON message.threadID = thread.id
                    WHERE message.date = (
                        SELECT max(date) FROM message WHERE threadID = thread.id
                    )
                    AND message.date <= ?
                    GROUP BY thread.id
                    ORDER BY message.date ASC
                    """, arguments: [cutoff])
                    .map { (try MailThread(row: $0), $0["newestSender"] as String? ?? "") }
            }

        // Sender matching happens in Swift because a header is
        // "Display Name <addr>" and only the bare address is comparable.
        return candidates
            .filter { Draft.normalizedAddress($0.newestSender) == mine }
            .map(\.thread)
    }
}
