import Foundation

/// Serialized coordinator for one account's Gmail sync. A single `syncNow()` pass
/// runs the initial backfill (only if not yet complete), then incremental sync,
/// then drains the outbound mutation queue. Overlapping calls are coalesced.
///
/// Scheduling/polling, on-focus refresh, offline backoff, and history-expired
/// auto-re-backfill are intentionally out of scope — `start()` is one `syncNow()`.
public actor GmailSync {
    private let accountID: String
    private let backfill: BackfillService
    private let incremental: IncrementalSyncService
    private let outbound: OutboundService
    private let syncState: SyncStateStore
    private let backfillLimit: Int
    private var isSyncing = false

    public init(accountID: String, backfill: BackfillService, incremental: IncrementalSyncService,
                outbound: OutboundService, syncState: SyncStateStore, backfillLimit: Int = 500) {
        self.accountID = accountID
        self.backfill = backfill
        self.incremental = incremental
        self.outbound = outbound
        self.syncState = syncState
        self.backfillLimit = backfillLimit
    }

    /// Runs one initial sync pass.
    public func start() async throws {
        try await syncNow()
    }

    /// Runs one serialized sync pass: backfill (if incomplete) → incremental → drain.
    /// A concurrent call while a pass is in flight is coalesced (returns immediately).
    public func syncNow() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let state = try syncState.load(accountID: accountID)
        if state?.backfillComplete != true {
            try await backfill.backfillInbox(accountID: accountID, maxMessages: backfillLimit)
        }
        try await incremental.sync(accountID: accountID)
        try await outbound.drain()
    }
}
