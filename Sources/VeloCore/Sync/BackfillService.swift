import Foundation

/// Pulls recent INBOX messages from Gmail and reconciles them into `MailStore`.
///
/// Reconciliation writes through `MailStore`'s upsert API, so re-running a
/// backfill produces the same rows rather than duplicates. On completion it
/// records the mailbox `historyId` baseline (captured up front, before listing)
/// and marks `backfillComplete`, so incremental sync can run without seeding.
public struct BackfillService: Sendable {
    private let source: GmailReading
    private let store: MailStore
    private let syncState: SyncStateStore

    public init(source: GmailReading, store: MailStore, syncState: SyncStateStore) {
        self.source = source
        self.store = store
        self.syncState = syncState
    }

    /// How many messages are hydrated at once. Bounded because 500 simultaneous
    /// requests would be rate-limited and would exhaust the connection pool.
    public static let maximumConcurrentFetches = 8

    /// How many are written per transaction. Small enough that the inbox starts
    /// filling almost immediately; large enough not to thrash SQLite.
    static let chunkSize = 20

    /// Hydrates one chunk concurrently, returning the messages in the order
    /// they were requested so reconciliation is deterministic.
    private func fetch(_ ids: [String]) async throws -> [GmailMessageDTO] {
        try await withThrowingTaskGroup(of: (Int, GmailMessageDTO).self) { group in
            var next = 0
            var results: [Int: GmailMessageDTO] = [:]

            func addTask(_ index: Int) {
                let id = ids[index]
                group.addTask { (index, try await self.source.getMessage(id: id)) }
            }

            while next < min(Self.maximumConcurrentFetches, ids.count) {
                addTask(next)
                next += 1
            }
            // Start a replacement as each finishes, so the group stays at the
            // cap rather than draining before the next batch begins.
            while let (index, dto) = try await group.next() {
                results[index] = dto
                if next < ids.count {
                    addTask(next)
                    next += 1
                }
            }
            return ids.indices.compactMap { results[$0] }
        }
    }

    /// Fetches up to `maxMessages` of the most recent INBOX messages, upserts
    /// their threads/messages, then records the sync cursor for `accountID`.
    public func backfillInbox(accountID: String, maxMessages: Int) async throws {
        // Capture the baseline BEFORE listing: messages arriving mid-backfill are
        // then re-delivered by history.list from this cursor (upserts make it idempotent).
        let profile = try await source.getProfile()
        let baseline = profile.historyId

        var ids: [String] = []
        var pageToken: String?
        repeat {
            let page = try await source.listInboxMessageIDs(pageToken: pageToken)
            ids.append(contentsOf: page.ids)
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < maxMessages
        ids = Array(ids.prefix(maxMessages))

        // Fetched in bounded-concurrency chunks and stored per chunk, which is
        // what the v1 design asked for: "store as we go so the inbox populates
        // progressively". Hydrating all 500 first meant an empty inbox for
        // minutes on a real account, and one failed fetch discarding every
        // message before it.
        for chunk in stride(from: 0, to: ids.count, by: Self.chunkSize).map({
            Array(ids[$0..<min($0 + Self.chunkSize, ids.count)])
        }) {
            let dtos = try await fetch(chunk)
            try InboxReconciler.reconcile(dtos, into: store)
        }

        // Persist the cursor only after reconcile succeeds.
        // Record the account's own address too: it is on the wire either way,
        // and without it a send has no correct `From` to use.
        try syncState.save(SyncState(accountID: accountID, historyId: baseline,
                                     backfillComplete: true,
                                     emailAddress: profile.emailAddress))
    }
}
