import Foundation

/// Applies per-message label deltas from Gmail history to local storage, then
/// re-derives the aggregate label/unread state of each affected thread.
public enum LabelDeltaApplier {
    public static func apply(_ deltas: [GmailHistoryResponse.LabelDelta], into store: MailStore) throws {
        var affectedThreads: Set<String> = []

        // Apply in order — re-reading each message so sequential deltas compose
        // (e.g. remove UNREAD then re-add it).
        for delta in deltas {
            guard var message = try store.message(id: delta.messageID) else { continue }
            let labels = Set(message.labelIDs).subtracting(delta.removed).union(delta.added).sorted()
            message.labelIDs = labels
            message.isUnread = labels.contains("UNREAD")
            try store.upsert(message)
            affectedThreads.insert(message.threadID)
        }

        for threadID in affectedThreads {
            let messages = try store.messages(inThread: threadID)
            let (labelIDs, isUnread) = GmailMessageMapper.threadAggregate(from: messages)
            try store.updateThreadDerivedLabels(labelIDs, isUnread: isUnread, onThread: threadID)
        }
    }
}
