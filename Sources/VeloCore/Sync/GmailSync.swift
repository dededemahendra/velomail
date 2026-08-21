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

        do {
            try await incremental.sync(accountID: accountID)
        } catch is SyncError {
            // Both SyncError cases mean the same thing: there is no usable
            // cursor. `historyExpired` is Gmail dropping history older than
            // about a week (leave the app closed over a holiday and every sync
            // fails); `notInitialized` is a baseline that was never set. A
            // re-backfill re-establishes the cursor, so recover in this pass
            // rather than surfacing an error the engine knows how to fix.
            try resetCursor()
            try await backfill.backfillInbox(accountID: accountID, maxMessages: backfillLimit)
            // Exactly one retry: a cursor that is still unusable after a fresh
            // backfill is a real fault, and retrying it in a loop would spin.
            try await incremental.sync(accountID: accountID)
        }

        try await outbound.drain()
    }

    /// Clears the cursor and the backfill flag so `backfillInbox` re-seeds both.
    private func resetCursor() throws {
        try syncState.save(SyncState(accountID: accountID, historyId: nil, backfillComplete: false))
    }
}
