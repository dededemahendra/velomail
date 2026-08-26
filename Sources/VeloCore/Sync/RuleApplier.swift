import Foundation

/// Runs the rule engine over threads and performs what it asks for.
///
/// Everything goes through `OutboundService`, so a rule-driven archive is
/// optimistic locally, pushed to Gmail, and reverted on failure exactly like one
/// the user typed. One path, one set of failure modes.
public struct RuleApplier: Sendable {
    private let engine: RuleEngine
    private let store: MailStore
    private let outbound: OutboundService

    public init(engine: RuleEngine, store: MailStore, outbound: OutboundService) {
        self.engine = engine
        self.store = store
        self.outbound = outbound
    }

    /// Applies rules to the given threads.
    ///
    /// Callers pass only threads that *just arrived*. Running this over a
    /// backfill would archive hundreds of messages the user had already dealt
    /// with, and every one of those is a real change pushed to every device.
    public func apply(toThreads threadIDs: [String]) throws {
        for threadID in threadIDs {
            // A thread is judged on what just arrived, not on how it started.
            guard let newest = try store.messages(inThread: threadID).last else { continue }
            let hasAttachment = try !store.attachments(forMessage: newest.id).isEmpty

            for action in engine.actions(for: newest, hasAttachment: hasAttachment) {
                try perform(action, on: threadID)
            }
        }
    }

    /// True when rules asked for this thread never to be seen, so it can be kept
    /// out of notifications.
    public func isBlocked(threadID: String) -> Bool {
        guard let newest = try? store.messages(inThread: threadID).last else { return false }
        return engine.isBlocked(newest)
    }

    private func perform(_ action: RuleAction, on threadID: String) throws {
        switch action {
        case .archive:
            try outbound.archive(threadID: threadID)
        case .star:
            try outbound.star(threadID: threadID)
        case .markRead:
            try outbound.markRead(threadID: threadID)
        case .markImportant:
            try outbound.star(threadID: threadID)   // STARRED is what the Important section reads
        case .block:
            // Read first, then archived: the reverse order would briefly leave
            // an unread badge for mail the user asked never to see.
            try outbound.markRead(threadID: threadID)
            try outbound.archive(threadID: threadID)
        }
    }
}
