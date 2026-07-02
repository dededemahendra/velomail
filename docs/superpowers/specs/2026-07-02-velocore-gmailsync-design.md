# VeloCore: GmailSync (headless backfill core) — Design

**Date:** 2026-07-02
**Status:** Draft — pending review
**Depends on:** VeloCore storage foundation + Auth token core (both on `master`)

## 1. Purpose

Provide the read path of Velo Mail's Gmail sync — turning a valid access token
into inbox threads/messages persisted in local `Storage` — built and tested
**headlessly**, without the GUI app or live Google network. This is the
"Using / refreshing" flow the Auth design (§5) deferred to GmailSync, plus the
initial-backfill pull the v1 design (§6) describes.

Success criterion: a `swift test` suite (no network, no GUI, no real Google
credentials) covers: obtaining a valid access token (refreshing when expired),
mapping Gmail API JSON into `MailThread`/`Message`, and reconciling a backfill
page into `MailStore` (insert + idempotent re-run).

## 2. Scope

### In scope (this increment)
- `AccessTokenProvider`: load `TokenSet` from `TokenStore`; if expired, refresh
  via `TokenService.refresh` and persist; return a valid access token. Maps a
  missing/absent refresh token to a re-auth-required signal.
- `GmailAPIClient`: thin read client over the injectable `HTTPClient` for
  `users.messages.list` (INBOX, paged) and `users.messages.get` (format=full).
  Adds the `Authorization: Bearer` header; maps non-2xx to typed errors.
- Gmail DTOs + mapping: decode Gmail's `Message`/`ListMessagesResponse` JSON and
  map to VeloCore `Message` (sender/recipients/subject/date/body/unread) and
  derive/update the parent `MailThread` (snippet, lastMessageDate, unread,
  labelIDs).
- `BackfillService`: pull the most-recent N INBOX threads and reconcile into
  `MailStore`; idempotent (re-running does not duplicate or corrupt rows).

### Out of scope (later increments)
- Incremental `history.list` sync + `sync_state` table (next increment).
- Outbound push / `pending_mutation` queue.
- `GmailAPIClient` for send / label-modify.
- Interactive sign-in, real OAuth credentials, live network.
- `GmailSync` background *actor* / scheduling — this increment delivers the
  reconciliation building blocks the actor will later drive.

## 3. Tech Stack

Same as VeloCore: Swift 6.1 (5.9 tools), SPM, Swift Testing, Command Line Tools
only. New code lives in the existing `VeloCore` target under
`Sources/VeloCore/Sync/`. No new third-party dependencies (Foundation + the
existing GRDB storage). Reuses the Auth core's `HTTPClient` seam — but note the
current `HTTPClient` only exposes `post`; see §7 Open Questions.

## 4. Components

All under `Sources/VeloCore/Sync/` unless noted.

| Unit | Responsibility | Depends on |
|---|---|---|
| `AccessTokenProvider` | `validAccessToken() async throws -> String`. Loads `TokenSet`; if `isExpired`, refreshes + saves; returns access token. No token / no refresh token → `.missingRefreshToken`. | `TokenStore`, `TokenService`, `TokenSet` |
| `GmailAPIClient` | `listInboxMessageIDs(pageToken:) `→ ids + nextPageToken; `getMessage(id:)` → `GmailMessageDTO`. Adds bearer header, maps non-2xx → `AuthError.server`/`.invalidResponse`. | `HTTPClient`, `AccessTokenProvider` |
| `GmailMessageDTO` + `GmailMessageMapper` | Decode Gmail JSON; map to VeloCore `Message` + derive `MailThread` fields (parse `payload.headers` for From/To/Subject/Date, choose HTML/text body part, `labelIds`, `internalDate`, `snippet`). | Foundation, `Message`, `MailThread` |
| `BackfillService` | `backfillInbox(maxThreads:) async throws`: page ids, hydrate, group by `threadId`, upsert threads+messages into `MailStore`. Idempotent. | `GmailAPIClient`, `GmailMessageMapper`, `MailStore` |
| `SyncError` (or reuse `AuthError`) | Typed errors for the sync layer. | — |

## 5. Data Flow (backfill)

1. `AccessTokenProvider.validAccessToken()` → bearer token (refresh if needed).
2. `GmailAPIClient.listInboxMessageIDs(pageToken:)` → `[id]` + `nextPageToken`,
   paged until `maxThreads` reached or no more pages.
3. For each id, `GmailAPIClient.getMessage(id:)` → `GmailMessageDTO`.
4. `GmailMessageMapper` → `Message` + parent `MailThread` fields.
5. Group messages by `threadID`; derive each `MailThread` (snippet from newest,
   `lastMessageDate` = max message date, `isUnread` = any UNREAD, union of
   `labelIDs`, `hasAttachments`).
6. `MailStore.upsert(thread)` then `MailStore.upsert(message)` for each — reusing
   the existing `PersistableRecord.save` upsert semantics, so re-runs are
   idempotent.

## 6. Testing

Deterministic `swift test` suite (no network, no GUI, no real credentials):
- `AccessTokenProvider` via `InMemoryTokenStore` + a mock `HTTPClient`
  (or an injected `TokenService` over a mock client): returns stored token when
  fresh; refreshes + persists when expired; reuses prior refresh token when the
  refresh response omits one; empty store or no refresh token → `.missingRefreshToken`.
- `GmailAPIClient` via mock `HTTPClient`: list parses ids + `nextPageToken`;
  get parses a full message; non-2xx → typed error; bearer header is attached.
- `GmailMessageMapper`: real recorded Gmail JSON fixtures → expected `Message`
  fields; header parsing (From/To/Subject/Date); HTML-vs-text body selection;
  base64url body decode; label mapping.
- `BackfillService` end-to-end against a scripted mock client over an in-memory
  `AppDatabase`: N messages across M threads reconcile into the expected inbox
  rows; **running twice yields the same rows** (idempotence); paging is followed.

Fixtures: small hand-written Gmail JSON payloads committed under
`Tests/VeloCoreTests/Fixtures/` (no live capture needed).

## 7. Open Questions (resolve before/at plan approval)

1. **`HTTPClient` needs GET.** The Auth `HTTPClient` protocol exposes only
   `post`. Gmail read calls are GET. Options: (a) extend the protocol with
   `get(url:headers:)`, (b) add a general `send(request:)`, or (c) a separate
   sync-side HTTP seam. Recommendation: (a) minimal `get` addition to the
   existing protocol + `URLSessionHTTPClient`, tested via the existing
   `StubURLProtocol`.
2. **Token provider concurrency.** Concurrent refreshes should be de-duplicated
   (single-flight) so N parallel `getMessage` calls don't each refresh. Ship
   serial-correct first; add single-flight in the sync-actor increment, or now?
3. **Backfill cap N.** Default most-recent-N threads for first paint (v1 design
   open question). Config value; pick a placeholder (e.g. 50) — non-blocking.
4. **`hasAttachments` derivation.** From `payload` MIME parts (any part with a
   `filename`)? Confirm heuristic.

## 8. Milestones (build order)

1. `AccessTokenProvider` (+ tests).  ← smallest, unblocks the rest
2. `HTTPClient.get` extension (+ StubURLProtocol test).
3. `GmailMessageDTO` + `GmailMessageMapper` (+ fixture tests).
4. `GmailAPIClient` (list + get) against mock `HTTPClient`.
5. `BackfillService` reconciliation + idempotence (+ end-to-end test).
