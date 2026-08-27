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

    /// The labels a sync pulls down. Inbox, plus the two that have views of
    /// their own: a Sent or Starred list holding only what happened in this app
    /// would show a handful of threads against a mailbox of thousands.
    ///
    /// Adding to this list is enough -- `SyncState` tracks each label
    /// separately, so an existing account fetches the new one on its next pass
    /// without re-fetching the rest.
    public static let backfilledLabels = ["INBOX", "SENT", "STARRED"]

    /// Fetches up to `maxMessages` of the most recent messages in each label
    /// that has not been fetched yet, upserts them, and records each label as
    /// it lands.
    ///
    /// Per label rather than all-or-nothing: adding a label to the app should
    /// pull that label's history without re-fetching a mailbox already here.
    public func backfillInbox(accountID: String, maxMessages: Int) async throws {
        // Capture the baseline BEFORE listing: messages arriving mid-backfill are
        // then re-delivered by history.list from this cursor (upserts make it idempotent).
        let profile = try await source.getProfile()
        let baseline = profile.historyId

        let existing = try syncState.load(accountID: accountID)
        let outstanding = (existing ?? SyncState(accountID: accountID, historyId: nil,
                                                 backfillComplete: false))
            .labelsNeedingBackfill(of: Self.backfilledLabels)
        guard !outstanding.isEmpty else { return }

        var ids: [String] = []
        var seen: Set<String> = []
        for label in outstanding {
            var pageToken: String?
            var forLabel: [String] = []
            repeat {
                let page = try await source.listMessageIDs(labelID: label, pageToken: pageToken)
                forLabel.append(contentsOf: page.ids)
                pageToken = page.nextPageToken
            } while pageToken != nil && forLabel.count < maxMessages
            // A replied-to thread is listed under both labels; hydrating it
            // twice would double the slowest part of a first sync.
            ids.append(contentsOf: forLabel.prefix(maxMessages).filter { seen.insert($0).inserted })
        }

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
        // The cursor is only moved on a first backfill. A later label's pass
        // must not rewind history to now, or everything that arrived since the
        // original sync would be skipped.
        let alreadySynced = existing?.backfillComplete == true
        try syncState.save(SyncState(
            accountID: accountID,
            historyId: alreadySynced ? existing?.historyId : baseline,
            backfillComplete: true,
            emailAddress: profile.emailAddress ?? existing?.emailAddress,
            backfilledLabels: (existing?.backfilledLabels ?? []) + outstanding))
    }
}
