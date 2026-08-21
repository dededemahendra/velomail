# VeloCore Build Plan — Increment F (Sync Scheduler & Resilience)

Execute **top to bottom**, red→green, one commit per task. `swift test` must be
green and the target must compile after every task.

Spec: `docs/superpowers/specs/2026-08-21-velocore-sync-scheduler-design.md`

## Migration ledger

B=v3, C=v4, E=v5. F claims **`v6_add_mutation_attempts`**, registered after v5.
Never renumber a shipped identifier. Schema tests assert by column existence.

## Shared-file edit ledger

| File | Tasks | Order |
|---|---|---|
| `Storage/MutationStore.swift` | F1 | once |
| `Storage/AppDatabase.swift` | F1 | once |
| `Models/PendingMutation.swift` | F1 | once |
| `Sync/GmailSync.swift` | F3, F4, F5 | strictly in that order |

---

## F1 — Bounded mutation retry (migration v6)

**Tests** (`AppDatabaseTests`, `MutationStoreTests`)
- `pendingMutationTableHasAttemptsColumn`
- `markFailedIncrementsAttempts`
- `retryFailedRequeuesFailedMutationsUnderTheCap`
- `retryFailedLeavesMutationsAtTheCapFailed`
- `retryFailedIgnoresPendingRows`

**Implementation** — `PendingMutation.attempts: Int` (default 0); migration
`v6_add_mutation_attempts`; `MutationStore.markFailed` increments;
`MutationStore.retryFailed(maxAttempts:)`.

## F2 — `BackoffPolicy` (pure)

**Tests** (`BackoffPolicyTests`)
- `firstFailureWaitsTheBaseDelay`
- `delayDoublesWithEachConsecutiveFailure`
- `delayIsClampedToTheCap`
- `zeroFailuresHasNoDelay`

**Implementation** — `Sync/BackoffPolicy.swift`: `base`, `multiplier`, `cap`,
`delay(afterFailures:) -> TimeInterval`. No clock, no randomness.

## F3 — Auto re-backfill on an expired cursor

**Tests** (`GmailSyncTests`)
- `historyExpiredResetsTheCursorAndReBackfillsInTheSamePass`
- `reBackfillIsAttemptedOnlyOncePerPass`
- `notInitializedAlsoTriggersABackfill`
- `aNormalPassDoesNotReBackfill`

**Implementation** — `GmailSync.syncNow()` catches `SyncError.historyExpired` /
`.notInitialized` from `incremental.sync`, clears `historyId` +
`backfillComplete`, runs `backfill`, then retries incremental **once**.

## F4 — `SyncStatus`

**Tests** (`GmailSyncTests`)
- `statusStartsIdle`
- `statusIsUpToDateAfterASuccessfulPass`
- `statusIsOfflineAfterATransientFailure`
- `aSuccessfulPassClearsTheFailureCount`
- `decodeFaultsPropagateRatherThanBecomingOffline`

**Implementation** — `SyncStatus` enum; `GmailSync.status` accessor; failure
counting inside `syncNow()`. Transient = `AuthError`; everything else rethrows.

## F5 — `SyncClock` + polling loop

**Tests** (`GmailSyncTests`, `SyncClockTests`)
- `runPollsRepeatedlyAtTheConfiguredInterval`
- `runSleepsForTheBackoffDelayAfterAFailedPass`
- `runStopsWhenTheTaskIsCancelled`
- `runRetriesFailedMutationsAtTheTopOfEachPass`

**Implementation** — `SyncClock` protocol (`now()`, `sleep(for:)`) +
`SystemSyncClock`; `GmailSync.run(interval:)`; injected clock defaulted in
`init`. Tests use a fake clock that records durations and ends the loop by
throwing `CancellationError`.

---

## Out of scope for F (recorded)

- On-focus refresh wiring (an app-lifecycle concern; engine exposes `syncNow()`).
- Gmail push (`watch` + Pub/Sub).
- Backoff jitter.
- A user-facing surface for permanently failed mutations — the UI increment owns it.
- `KeyboardEngine` and the SwiftUI/AppKit layer — still blocked on an app target
  and real Google OAuth client credentials.

---

## Completion record

All five tasks landed red→green, one commit each. Suite went 181 → 212 tests,
clean build, no warnings.

**One defect found in the post-implementation review, fixed with reproducing
tests first:** `syncNow` only handled `AuthError` in its failure path, so any
other error (a cursor still dead after a re-backfill, a storage fault) left
`status` stuck on `.syncing` — a UI would have shown a spinner forever — and
contributed nothing to the failure count, so `run()` kept retrying such a
failure at the full poll rate. Now every failure counts toward backoff, and only
the reported status distinguishes transient (`.offline`) from unlikely-to-clear
(`.failed(reason:)`).

**Environment note:** partway through this increment `xcode-select` was pointing
at `/Library/Developer/CommandLineTools`, which ships the swift-testing macro
plugin but no `Testing.swiftmodule`, so every test file failed with
`no such module 'Testing'`. Worked around per-invocation with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. The
permanent fix is
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

**Still deferred after F:** on-focus refresh wiring (an app-lifecycle concern),
Gmail push (`watch` + Pub/Sub), backoff jitter, a user-facing surface for
permanently failed mutations, attachments, `users.drafts.*`, and the whole UI
layer (`KeyboardEngine`, SwiftUI/AppKit), which remains blocked on an app target
and real Google OAuth client credentials.
