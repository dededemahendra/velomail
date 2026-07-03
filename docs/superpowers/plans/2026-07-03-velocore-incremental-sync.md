# VeloCore GmailSync Incremental (history.list) Implementation Plan

**Goal:** Keep the local inbox current after backfill — pull `users.history.list`
deltas since a stored `historyId`, reconcile newly arrived messages into
`Storage`, and advance the cursor — all headless and unit-tested.

**Architecture:** New code in the existing `VeloCore` target. `SyncStateStore`
under `Storage/`; history DTO, reconciler, and service under `Sync/`. Reuses the
backfill core's `HTTPClient.get`, `AccessTokenProvider`, `GmailMessageMapper`,
and `GmailReading` seam.

## Global Constraints

- Swift Testing (not XCTest). Extract throwing calls to a `let` before `#expect`.
- No new third-party dependencies. Deterministic suite: no network/GUI/credentials.
- Commit per task, trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Branch `feat/velocore-incremental-sync` (off `master`).

---

### Task 1: sync_state table + SyncStateStore

**Files:** create `Sources/VeloCore/Storage/SyncState.swift`, `Sources/VeloCore/Storage/SyncStateStore.swift`; edit `AppDatabase.swift` (new migration); test `Tests/VeloCoreTests/SyncStateStoreTests.swift`.

- Migration `v2_create_sync_state`: table `syncState` — `accountID` text pk, `historyId` text (nullable), `backfillComplete` bool not null default false.
- `SyncState: Codable, FetchableRecord, PersistableRecord, Equatable` with `databaseTableName = "syncState"`.
- `SyncStateStore(_ db: AppDatabase)`: `load(accountID:) throws -> SyncState?`, `save(_:) throws`.
- [ ] Failing test: save/load round-trip; missing accountID → nil; historyId update persists.
- [ ] Implement. Verify green + full suite. Commit.

---

### Task 2: GmailHistoryResponse DTO

**Files:** create `Sources/VeloCore/Sync/GmailHistoryResponse.swift`; test `Tests/VeloCoreTests/GmailHistoryResponseTests.swift`.

- `GmailHistoryResponse: Decodable, Equatable` — `history: [Record]?`, `historyId: String?`, `nextPageToken: String?`. `Record.messagesAdded: [Added]?`, `Added.message.id`. Computed `addedMessageIDs: [String]`.
- [ ] Failing test (inline JSON): ids across multiple records; empty/absent `history` → []; parses `historyId` + `nextPageToken`.
- [ ] Implement. Verify green + full suite. Commit.

---

### Task 3: GmailAPIClient.fetchHistory

**Files:** edit `Sources/VeloCore/Sync/GmailAPIClient.swift` (add method + `GmailReading` requirement); edit existing `GmailReading` mocks in `BackfillServiceTests.swift` (trapping stub); test `Tests/VeloCoreTests/GmailAPIClientTests.swift`.

- Add `fetchHistory(startHistoryId:pageToken:) async throws -> GmailHistoryResponse` to `GmailReading` and `GmailAPIClient`: GET `users/me/history?startHistoryId=…&historyTypes=messageAdded` (+ `pageToken`), bearer, `checkedDecode`.
- [ ] Failing test: URL has `startHistoryId`/`historyTypes`, bearer attached, parses response, non-2xx → typed error.
- [ ] Implement (add trapping `fetchHistory` to the backfill test's `ScriptedSource`). Verify green + full suite. Commit.

---

### Task 4: InboxReconciler extraction

**Files:** create `Sources/VeloCore/Sync/InboxReconciler.swift`; edit `BackfillService.swift` to use it; tests unchanged (regression guard).

- `enum InboxReconciler { static func reconcile(_ dtos: [GmailMessageDTO], into store: MailStore) throws }` — the group-by-thread + upsert loop currently inline in `BackfillService`.
- [ ] Refactor `BackfillService` to call it. Run `BackfillServiceTests` (must stay green — no behavior change). Commit.

---

### Task 5: IncrementalSyncService

**Files:** create `Sources/VeloCore/Sync/IncrementalSyncService.swift`, `Sources/VeloCore/Sync/SyncError.swift`; test `Tests/VeloCoreTests/IncrementalSyncServiceTests.swift`.

- `SyncError: Error, Equatable { case notInitialized }`.
- `sync(accountID:) async throws`: load `historyId` (else `.notInitialized`); page `fetchHistory`, collect `addedMessageIDs` + latest `historyId`; dedupe; `getMessage` each; `InboxReconciler.reconcile`; save advanced `historyId`.
- [ ] Failing end-to-end test via scripted `GmailReading` + in-memory DB seeded with a `historyId`: added messages land in inbox; cursor advances; second run idempotent; paging followed; absent cursor → `.notInitialized`.
- [ ] Implement. Verify green + full suite. Commit.

## Deferred (not in this plan)

- Per-message `labelsAdded`/`labelsRemoved` (needs message-labels schema decision).
- Initial `historyId` baseline (backfill/getProfile wiring).
- History-expired (404) → rebackfill policy.
- Outbound push; `GmailSync` background actor / scheduling.
