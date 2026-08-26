import Foundation
import GRDB

/// Numbers about how mail actually flows, derived from what is already stored.
///
/// Nothing is recorded to produce these — no event log, no counters, nothing to
/// go stale or drift out of step with the mailbox. The cost is that the window
/// is limited to what has been synced, which is stated where it is shown.
public struct MailAnalytics: Sendable {
    public struct Day: Equatable, Sendable {
        public let day: Date
        public let received: Int
        public let sent: Int
    }

    public struct Report: Equatable, Sendable {
        public let received: Int
        public let sent: Int
        /// Seconds between an inbound message and your reply, median across
        /// threads. `nil` when nothing has been replied to.
        public let medianResponse: TimeInterval?
        /// One entry per day in the window, oldest first, including quiet days.
        public let daily: [Day]
        /// Hour of day (0–23) that receives the most mail.
        public let busiestHour: Int?
    }

    private let store: MailStore

    public init(_ store: MailStore) {
        self.store = store
    }

    public func report(identity: String, days: Int = 7, now: Date = Date(),
                       calendar: Calendar = .current) throws -> Report {
        let mine = Draft.normalizedAddress(identity)
        let start = calendar.date(byAdding: .day, value: -(days - 1),
                                  to: calendar.startOfDay(for: now)) ?? now

        let messages = try store.database.dbQueue.read { db in
            try Message.filter(sql: "date >= ?", arguments: [start])
                .order(sql: "date ASC")
                .fetchAll(db)
        }

        let isMine = { (message: Message) in Draft.normalizedAddress(message.sender) == mine }
        let received = messages.filter { !isMine($0) }
        let sent = messages.filter(isMine)

        // Every day in the window, so a quiet day is a zero rather than a gap --
        // a missing point in a chart reads as missing data.
        var byDay: [Date: (received: Int, sent: Int)] = [:]
        for message in messages {
            let day = calendar.startOfDay(for: message.date)
            var counts = byDay[day] ?? (0, 0)
            if isMine(message) { counts.sent += 1 } else { counts.received += 1 }
            byDay[day] = counts
        }
        let daily = (0..<days).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let counts = byDay[calendar.startOfDay(for: day)] ?? (0, 0)
            return Day(day: day, received: counts.received, sent: counts.sent)
        }

        var busiest: Int?
        if !received.isEmpty {
            let hours = Dictionary(grouping: received) { calendar.component(.hour, from: $0.date) }
            busiest = hours.max { lhs, rhs in
                // Ties break to the earlier hour, so the answer is stable.
                (lhs.value.count, -lhs.key) < (rhs.value.count, -rhs.key)
            }?.key
        }

        return Report(received: received.count,
                      sent: sent.count,
                      medianResponse: try medianResponse(mine: mine),
                      daily: daily,
                      busiestHour: busiest)
    }

    // MARK: - Response time

    /// Median seconds from an inbound message to your first reply after it.
    ///
    /// Median rather than mean: one message left for a week would drag an
    /// average somewhere that describes nothing.
    private func medianResponse(mine: String) throws -> TimeInterval? {
        let threads = try store.database.dbQueue.read { db in
            try MailThread.fetchAll(db)
        }

        var gaps: [TimeInterval] = []
        for thread in threads {
            let messages = try store.messages(inThread: thread.id)
            var lastInbound: Date?
            for message in messages {
                let isMine = Draft.normalizedAddress(message.sender) == mine
                if isMine {
                    // Only the first reply after an inbound one counts; following
                    // up on yourself is not a second response.
                    if let inbound = lastInbound {
                        gaps.append(message.date.timeIntervalSince(inbound))
                        lastInbound = nil
                    }
                } else {
                    lastInbound = message.date
                }
            }
        }

        guard !gaps.isEmpty else { return nil }
        let sorted = gaps.sorted()
        return sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
}
