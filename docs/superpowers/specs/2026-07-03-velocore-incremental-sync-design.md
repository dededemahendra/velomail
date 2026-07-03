# VeloCore: GmailSync Incremental (history.list) — Design

**Date:** 2026-07-03
**Status:** Draft — pending review
**Depends on:** GmailSync backfill core (on `master`)

## 1. Purpose

Keep the local inbox current after the initial backfill by pulling Gmail's
`users.history.list` deltas since a stored `historyId` and reconciling **newly
arrived messages** into `Storage` — built and tested headlessly.

Success criterion: a `swift test` suite (no network/GUI/credentials) covers a
`sync_state` store, history fetching + paging, applying `messagesAdded` into the
inbox, and advancing the stored `historyId` cursor — all idempotent.

## 2. Scope

### In scope (this increment)
- `sync_state` table + `SyncStateStore`: persist per-account `historyId` and
  `backfillComplete`.
- `GmailAPIClient.fetchHistory(startHistoryId:pageToken:)` (reuses the existing
  `HTTPClient.get` + bearer plumbing) + history DTOs.
- `IncrementalSyncService.sync(accountID:)`: page history since the stored
  `historyId`, hydrate each added message via `getMessage`, reconcile into
  `MailStore`, advance the stored `historyId`.
- Extract the backfill's group-by-thread-and-upsert step into a shared
  `InboxReconciler` (used by both `BackfillService` and the new service).

### Out of scope (deferred, needs its own design)
- **Per-message `labelsAdded` / `labelsRemoved` deltas.** Gmail labels are
  per-message; our schema tracks labels at the *thread* level and `Message` has
  no `labelIDs` column. Correctly folding per-message label removals into a
  multi-message thread (e.g. "is the thread still UNREAD?") needs a
  message-labels schema decision — deferred to a follow-up increment.
- Establishing the *initial* `historyId` baseline (from `getProfile` or the
  backfill). This increment treats a stored `historyId` as a precondition and
  throws `SyncError.notInitialized` when absent.
- History-expired (HTTP 404) → force-rebackfill handling (propagated as
  `.server` for now; policy belongs to the sync actor).
- Outbound push; the `GmailSync` background actor / scheduling.

## 3. Components

`SyncStateStore` under `Sources/VeloCore/Storage/`; the rest under `Sources/VeloCore/Sync/`.

| Unit | Responsibility | Depends on |
|---|---|---|
| `SyncState` | `PersistableRecord`: `accountID` (pk), `historyId: String?`, `backfillComplete: Bool`. | GRDB |
| `SyncStateStore` | `load(accountID:)` / `save(_:)` over `AppDatabase`. | `AppDatabase` |
| `GmailHistoryResponse` (+ nested) | Decode `history[].messagesAdded[].message.id`, top-level `historyId`, `nextPageToken`. Exposes `addedMessageIDs`. | Foundation |
| `GmailAPIClient.fetchHistory` | GET `users/me/history?startHistoryId=…&historyTypes=messageAdded`. Added to `GmailReading`. | `HTTPClient`, `AccessTokenProvider` |
| `InboxReconciler` | `reconcile(_ dtos:into: MailStore)`: group by thread, upsert thread + messages (extracted from `BackfillService`). | `GmailMessageMapper`, `MailStore` |
| `IncrementalSyncService` | `sync(accountID:)`: page history, hydrate added ids, reconcile, advance cursor. | `GmailReading`, `MailStore`, `SyncStateStore` |
| `SyncError` | `.notInitialized`. | — |

## 4. Data Flow (incremental sync)

1. `SyncStateStore.load(accountID:)?.historyId` → start cursor (else `.notInitialized`).
2. `fetchHistory(startHistoryId:pageToken:)` looped over `nextPageToken`,
   collecting `addedMessageIDs` and the latest response `historyId`.
3. Dedupe added ids (preserve order).
4. `getMessage(id:)` each → `GmailMessageDTO`.
5. `InboxReconciler.reconcile(dtos, into: store)` — same upsert path as backfill,
   so re-running is idempotent.
6. `SyncStateStore.save` with the advanced `historyId`.

## 5. Testing

Deterministic `swift test`:
- `SyncStateStore`: save/load round-trip over in-memory `AppDatabase`; missing → nil; historyId update.
- `GmailHistoryResponse`: decode from JSON fixture; `addedMessageIDs` across records; empty `history` → [].
- `GmailAPIClient.fetchHistory`: mock `HTTPClient` — URL has `startHistoryId`/`historyTypes`, bearer attached, parses response, non-2xx → typed error.
- `IncrementalSyncService` end-to-end via a scripted `GmailReading` + in-memory DB seeded with a `historyId`: added messages land in the inbox; cursor advances to the response `historyId`; **second run is a no-op on identical rows** (idempotence); paging followed; absent cursor → `.notInitialized`.

## 6. Milestones (build order)

1. `sync_state` migration + `SyncState` + `SyncStateStore`.
2. `GmailHistoryResponse` DTO (+ fixture tests).
3. `GmailAPIClient.fetchHistory` (+ `GmailReading` extension).
4. `InboxReconciler` extraction (refactor `BackfillService` to use it; tests stay green).
5. `IncrementalSyncService` (+ end-to-end tests).
