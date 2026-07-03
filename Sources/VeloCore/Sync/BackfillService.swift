import Foundation

/// Pulls recent INBOX messages from Gmail and reconciles them into `MailStore`.
///
/// Reconciliation writes through `MailStore`'s upsert API, so re-running a
/// backfill produces the same rows rather than duplicates. On completion it
/// records the mailbox `historyId` baseline (captured up front, before listing)
/// and marks `backfillComplete`, so incremental sync can run without seeding.
public struct BackfillService {
    private let source: GmailReading
    private let store: MailStore
    private let syncState: SyncStateStore

    public init(source: GmailReading, store: MailStore, syncState: SyncStateStore) {
        self.source = source
        self.store = store
        self.syncState = syncState
    }

    /// Fetches up to `maxMessages` of the most recent INBOX messages, upserts
    /// their threads/messages, then records the sync cursor for `accountID`.
    public func backfillInbox(accountID: String, maxMessages: Int) async throws {
        // Capture the baseline BEFORE listing: messages arriving mid-backfill are
        // then re-delivered by history.list from this cursor (upserts make it idempotent).
        let baseline = try await source.getProfile().historyId

        var ids: [String] = []
        var pageToken: String?
        repeat {
            let page = try await source.listInboxMessageIDs(pageToken: pageToken)
            ids.append(contentsOf: page.ids)
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < maxMessages
        ids = Array(ids.prefix(maxMessages))

        var dtos: [GmailMessageDTO] = []
        for id in ids {
            dtos.append(try await source.getMessage(id: id))
        }

        try InboxReconciler.reconcile(dtos, into: store)

        // Persist the cursor only after reconcile succeeds.
        try syncState.save(SyncState(accountID: accountID, historyId: baseline, backfillComplete: true))
    }
}
