import Foundation

/// Reconciles fetched Gmail messages into local storage: groups by thread,
/// derives the thread record, and upserts thread + messages. Shared by backfill
/// and incremental sync; upserts make re-runs idempotent.
public enum InboxReconciler {
    public static func reconcile(_ dtos: [GmailMessageDTO], into store: MailStore) throws {
        for (_, threadDTOs) in Dictionary(grouping: dtos, by: { $0.threadId }) {
            if let thread = GmailMessageMapper.thread(from: threadDTOs) {
                try store.upsert(thread)
            }
            for dto in threadDTOs {
                try store.upsert(GmailMessageMapper.message(from: dto))
            }
        }
    }
}
