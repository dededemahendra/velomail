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
    private let now: () -> Date
    private let clock: SyncClock
    private let backoff: BackoffPolicy
    private let maxMutationAttempts: Int
    private var isSyncing = false
    private var consecutiveFailures = 0

    /// The engine's current state, for a status indicator. Read-only from
    /// outside; only a pass changes it.
    public private(set) var status: SyncStatus = .idle

    public init(accountID: String, backfill: BackfillService, incremental: IncrementalSyncService,
                outbound: OutboundService, syncState: SyncStateStore, backfillLimit: Int = 500,
                now: @escaping () -> Date = { Date() }, clock: SyncClock = SystemSyncClock(),
                backoff: BackoffPolicy = .standard, maxMutationAttempts: Int = 3) {
        self.accountID = accountID
        self.backfill = backfill
        self.incremental = incremental
        self.outbound = outbound
        self.syncState = syncState
        self.backfillLimit = backfillLimit
        self.now = now
        self.clock = clock
        self.backoff = backoff
        self.maxMutationAttempts = maxMutationAttempts
    }

    /// Polls until cancelled: a pass, then a wait, forever.
    ///
    /// The wait is the poll `interval` after a good pass and the backoff delay
    /// after a bad one, so a dropped connection is retried quickly at first and
    /// then ever more patiently, instead of hammering an API that is not
    /// answering. Failures are already recorded in `status` by `syncNow`, so
    /// they are deliberately swallowed here -- the loop's job is to keep going.
    public func run(interval: TimeInterval) async {
        while !Task.isCancelled {
            try? await syncNow()

            let delay = consecutiveFailures > 0
                ? backoff.delay(afterFailures: consecutiveFailures)
                : interval
            do {
                try await clock.sleep(for: delay)
            } catch {
                return   // cancelled
            }
        }
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
        status = .syncing
        defer { isSyncing = false }

        do {
            try await runPass()
        } catch {
            // Every failure counts toward backoff -- something that will not fix
            // itself must not be retried at full rate either. Only the reported
            // status distinguishes them: AuthError is a dropped connection or a
            // 5xx and will likely clear, anything else (a cursor still dead
            // after a re-backfill, a storage fault) will not.
            //
            // Rethrown either way: swallowing here would hide a real failure
            // from anyone driving syncNow() directly, and would leave status
            // stuck on .syncing.
            consecutiveFailures += 1
            status = error is AuthError
                ? .offline(consecutiveFailures: consecutiveFailures)
                : .failed(reason: String(describing: error))
            throw error
        }

        consecutiveFailures = 0
        status = .upToDate(lastSyncedAt: now())
    }

    /// One pass: backfill (if needed) → incremental (recovering a dead cursor)
    /// → drain.
    private func runPass() async throws {
        // Give previously-failed writes another go before pulling, so a write
        // that lost a connection goes out on the next tick rather than waiting
        // for the user to touch the thread again.
        try outbound.retryFailed(maxAttempts: maxMutationAttempts)

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
