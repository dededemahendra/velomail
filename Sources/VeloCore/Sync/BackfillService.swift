import Foundation

/// Pulls recent INBOX messages from Gmail and reconciles them into `MailStore`.
///
/// Reconciliation writes through `MailStore`'s upsert API, so re-running a
/// backfill produces the same rows rather than duplicates.
public struct BackfillService {
    private let source: GmailReading
    private let store: MailStore

    public init(source: GmailReading, store: MailStore) {
        self.source = source
        self.store = store
    }

    /// Fetches up to `maxMessages` of the most recent INBOX messages (following
    /// paging as needed), then upserts their threads and messages into the store.
    public func backfillInbox(maxMessages: Int) async throws {
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
    }
}
