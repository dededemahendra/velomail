# VeloCore GmailSync (Headless Backfill Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the read path of Velo Mail's Gmail sync — a valid-access-token
provider, a Gmail read API client, Gmail JSON → VeloCore model mapping, and an
idempotent inbox backfill into `Storage` — all unit-tested without network, GUI,
or real Google credentials.

**Architecture:** New code lives in the existing `VeloCore` SPM target under
`Sources/VeloCore/Sync/`. All network access goes through the Auth core's
injectable `HTTPClient` protocol so tests never touch the network. Reconciliation
writes through the existing `MailStore` upsert API, so re-runs are idempotent.

**Tech Stack:** Swift 6.1 (5.9 tools), SPM, Swift Testing, Foundation + GRDB
(existing). No new third-party dependencies. Command Line Tools only.

## Global Constraints

- New source files under `Sources/VeloCore/Sync/`; tests under `Tests/VeloCoreTests/`; JSON fixtures under `Tests/VeloCoreTests/Fixtures/`.
- Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) — NOT XCTest.
- Do NOT write `#expect(try someThrowingCall())`. Extract to a local `let` first.
- No new third-party dependencies.
- Deterministic default suite: no real network, no real credentials.
- Commit after every task with trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Work on branch `feat/velocore-gmailsync` (created off `master`).

---

### Task 1: AccessTokenProvider  ✅ DONE (commit 4699580)

`validAccessToken() async throws -> String`: load `TokenSet`; return access token
when fresh; refresh via `TokenService.refresh` + persist when expired; empty
store or no refresh token → `.missingRefreshToken`. Tested with `InMemoryTokenStore`
+ mock `HTTPClient`.

---

### Task 2: HTTPClient.get extension

**Decision needed (design §7 Q1):** Gmail read calls are GET; the Auth
`HTTPClient` only has `post`. Recommended: add `get(url:headers:) async throws -> (Data, HTTPURLResponse)`
to the protocol + `URLSessionHTTPClient`.

**Files:** edit `Sources/VeloCore/Auth/HTTPClient.swift`; test `Tests/VeloCoreTests/URLSessionHTTPClientTests.swift` (extend, reuse existing `StubURLProtocol`).

- [ ] Failing test: `get` issues a GET, attaches headers, round-trips body + status via `StubURLProtocol`.
- [ ] Implement `get` symmetric to `post` (method "GET", no body).
- [ ] Verify green + full suite. Commit.

**Note:** every existing `HTTPClient` conformer (`MockHTTPClient` in the auth
tests) must add the `get` stub — or give the protocol a default `get`
implementation that traps, so only clients that need it override it.

---

### Task 3: GmailMessageDTO + GmailMessageMapper

Decode Gmail `users.messages.get` (format=full) JSON and map to VeloCore
`Message`, deriving `MailThread` fields.

**Files:** create `Sources/VeloCore/Sync/GmailMessageDTO.swift`, `Sources/VeloCore/Sync/GmailMessageMapper.swift`; fixtures `Tests/VeloCoreTests/Fixtures/gmail_message_full.json` (+ a text-only and an HTML variant); test `Tests/VeloCoreTests/GmailMessageMapperTests.swift`.

**Interfaces:**
- `GmailMessageDTO: Decodable` — `id`, `threadId`, `labelIds: [String]?`, `snippet`, `internalDate: String` (ms since epoch, string), `payload` (headers `[{name,value}]`, `mimeType`, `body {data?}`, `parts: [payload]?`).
- `enum GmailMessageMapper` — `message(from: GmailMessageDTO) -> Message` and a thread-derivation helper.

**Mapping rules (confirm in review):**
- `date` from `internalDate` (ms → `Date`).
- `sender` = `From` header; `recipients` = `To` header split on `,`.
- `subject` = `Subject` header (default "").
- `isUnread` = `labelIds` contains `"UNREAD"`.
- Body: prefer `text/html` part, else `text/plain`; base64url-decode `body.data` (Gmail uses URL-safe base64, `-`/`_`).
- Thread derivation (multiple messages): `snippet` from newest message, `lastMessageDate` = max date, `isUnread` = any UNREAD, `labelIDs` = union, `hasAttachments` = any part with a non-empty `filename` (design §7 Q4).

- [ ] Failing tests per rule using committed fixtures.
- [ ] Implement DTO + mapper.
- [ ] Verify green + full suite. Commit.

---

### Task 4: GmailAPIClient (list + get)

Thin read client over `HTTPClient` + `AccessTokenProvider`.

**Files:** create `Sources/VeloCore/Sync/GmailAPIClient.swift`; test `Tests/VeloCoreTests/GmailAPIClientTests.swift`.

**Interfaces:**
- `listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?)` — GET `users/me/messages?labelIds=INBOX&pageToken=…`.
- `getMessage(id: String) async throws -> GmailMessageDTO` — GET `users/me/messages/{id}?format=full`.
- Both call `AccessTokenProvider.validAccessToken()` and set `Authorization: Bearer …`; non-2xx → `AuthError.server`/`.invalidResponse`.

- [ ] Failing tests via mock `HTTPClient`: list parses ids + nextPageToken; get parses DTO; bearer header attached; non-2xx maps to typed error.
- [ ] Implement client.
- [ ] Verify green + full suite. Commit.

---

### Task 5: BackfillService (reconciliation + idempotence)

Pull the most-recent N INBOX threads and reconcile into `MailStore`.

**Files:** create `Sources/VeloCore/Sync/BackfillService.swift`; test `Tests/VeloCoreTests/BackfillServiceTests.swift`.

**Interface:** `backfillInbox(maxThreads: Int) async throws` — page ids (follow `nextPageToken` until `maxThreads` message ids collected or pages exhausted), hydrate each via `getMessage`, group by `threadID`, derive threads, `MailStore.upsert(thread)` then `upsert(message)`.

- [ ] Failing end-to-end test against a scripted mock `GmailAPIClient` (or mock `HTTPClient`) over an in-memory `AppDatabase`: N messages across M threads produce expected inbox rows; **running twice yields identical rows** (idempotence); paging is followed; `maxThreads` cap respected.
- [ ] Implement service.
- [ ] Verify green + full suite. Commit.

---

## Open questions to resolve before starting (design §7)

1. `HTTPClient.get` vs `send(request:)` vs separate seam — Task 2 assumes `get`.
2. Single-flight refresh in `AccessTokenProvider` — deferred to the sync-actor increment unless wanted now.
3. Backfill cap N default (placeholder 50).
4. `hasAttachments` heuristic (any part with a `filename`).

## Next increments (not in this plan)

- Incremental `history.list` sync + `sync_state` table.
- Outbound push (`pending_mutation` queue): send, label-modify.
- `GmailSync` background actor / scheduling that drives these building blocks.
