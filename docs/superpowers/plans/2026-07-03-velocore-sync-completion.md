# VeloCore Unified Build Plan — Increments A → B → C → D

This is the single, ordered, conflict-free TDD build plan for the four designed increments. Execute tasks **top to bottom**. Every task is red→green: write the listed test cases first, then the implementation, then run `swift test` (the whole target must compile after each task).

## Global sequencing decision

| Phase | Increment | Why this position | Migration(s) added |
|------|-----------|-------------------|--------------------|
| 1 | **A** — read-loop (historyId baseline + 404 recovery) | No migration; establishes `getProfile` on `GmailReading` that every later test double must conform to; establishes the backfill cursor/flag that D relies on. Do first so the protocol change lands once. | none |
| 2 | **B** — outbound (pending_mutation queue + modify) | First increment to add a migration. Claims **`v3_create_pending_mutation`**. Independent of A/C but must precede D (actor drains its queue). | **v3** |
| 3 | **C** — per-message labels | Soft-depends on B for migration ordering only. B already took v3, so C **rebases to `v4_add_message_labelIDs`** and registers after v3. Builds on A's incremental-sync path. | **v4** |
| 4 | **D** — GmailSync actor | Orchestration only, no schema. Depends on A (cursor/flag), B (drain + queue), C (full sync surface). Must be last. | none |

**Migration collision resolution (explicit):** B = `v3_create_pending_mutation`, C = `v4_add_message_labelIDs`. Never renumber a shipped identifier; `.registerMigration` calls stay in ascending order after `v2_create_sync_state`. **All schema tests assert by column/table existence, never by migration count/version**, so they survive any future rebase.

---

## Shared-file edit ledger (files touched by >1 increment)

Edit these files in the increment order shown; each later edit must build on the earlier one.

| File | Edited by (in order) | What each edit does |
|------|----------------------|---------------------|
| **`Sources/VeloCore/Sync/GmailAPIClient.swift`** | A → B → C → D | A: add `GmailProfile` + `getProfile()` to `GmailReading` protocol & client. B: declare `GmailWriting` inline + `modifyMessage` + `authorizedPOST`. C: add `historyTypes=labelAdded/labelRemoved` query items to `fetchHistory`. D: mark client `@unchecked Sendable`, protocol `: Sendable`. |
| **`GmailReading` protocol** (in GmailAPIClient.swift) | A → D | A: add `func getProfile() async throws -> GmailProfile`. D: `public protocol GmailReading: Sendable`. |
| **`Sources/VeloCore/Storage/AppDatabase.swift`** | B → C → D | B: append `v3_create_pending_mutation`. C: append `v4_add_message_labelIDs`. D: `public final class AppDatabase: Sendable`. Never reorder v1/v2/v3/v4. |
| **`Sources/VeloCore/Storage/MailStore.swift`** | B → C → D | B: add `thread(id:)`. C: add `message(id:)` + `updateThreadDerivedLabels(_:isUnread:onThread:)`. D: `: Sendable`. |
| **`Sources/VeloCore/Sync/IncrementalSyncService.swift`** | A → C → D | A: wrap `fetchHistory` in do/catch → `SyncError.historyExpired`. C: accumulate `labelDeltas`, call `LabelDeltaApplier.apply` after reconcile. D: `struct … : Sendable`. |
| **`Sources/VeloCore/Sync/BackfillService.swift`** | A → D | A: new `init(source:store:syncState:)` + `backfillInbox(accountID:maxMessages:)` capturing baseline. D: `: Sendable`. |
| **`Sources/VeloCore/Storage/SyncStateStore.swift`** | D | D: `: Sendable`. |
| **`Message.swift`, `GmailHistoryResponse.swift`** | C only | Single-increment, listed here so reviewers know C owns them. |
| **Test doubles `HistorySource` / `ScriptedSource`** | A → D | A: add `getProfile` conformance. D: annotate `@unchecked Sendable`. |

---

# PHASE 1 — Increment A (read loop)

## Task A1 — `GmailProfile` DTO + `getProfile()` on `GmailReading` and `GmailAPIClient`

**Files**
- create `Sources/VeloCore/Sync/GmailProfile.swift`
- edit `Sources/VeloCore/Sync/GmailAPIClient.swift`
- create `Tests/VeloCoreTests/GmailProfileTests.swift`
- edit `Tests/VeloCoreTests/GmailAPIClientTests.swift`, `IncrementalSyncServiceTests.swift`, `BackfillServiceTests.swift`

**Interfaces**
```swift
// Sources/VeloCore/Sync/GmailProfile.swift
public struct GmailProfile: Decodable, Equatable {
    public let emailAddress: String
    public let historyId: String   // Gmail sends a quoted string; keep as String, never parse to Int
}

// Add to GmailReading protocol:
func getProfile() async throws -> GmailProfile

// GmailAPIClient (reuses authorizedGET + checkedDecode; no query items):
public func getProfile() async throws -> GmailProfile {
    let url = baseURL.appendingPathComponent("users/me/profile")
    let (data, response) = try await authorizedGET(url)
    return try checkedDecode(data, response)
}
```
Compile-keeping stubs added the same step:
- `HistorySource` (IncrementalSyncServiceTests): `func getProfile() async throws -> GmailProfile { fatalError("getProfile not used by incremental sync") }`
- `ScriptedSource` (BackfillServiceTests): returns a scripted `GmailProfile` (fully wired in A2).

**Gmail request/response shape** — `GET users/me/profile` → `{"emailAddress":"u@x.com","historyId":"5000","messagesTotal":123,"threadsTotal":45}`. `Decodable` ignores `messagesTotal`/`threadsTotal` (present or absent).

**Test cases**
1. `GmailProfile` decodes `emailAddress`+`historyId`, ignores `messagesTotal`/`threadsTotal` when present.
2. `GmailProfile` decodes when those integer fields are absent.
3. `getProfile()` GETs `users/me/profile`, header `Authorization == "Bearer tok"`, parses fields — bind DTO to a `let`, then `#expect` on fields (no `#expect(try …)`).
4. `fetchHistory` 404 body `{"error":{"code":404,"status":"NOT_FOUND",…}}` maps via `checkedDecode` to `AuthError.server(code: "NOT_FOUND", …)` using `await #expect(throws:)` — documents the exact code A3 keys on.
5. Whole test target compiles: `HistorySource`/`ScriptedSource` gain `getProfile` so existing suites stay green.

---

## Task A2 — BackfillService establishes historyId baseline + `backfillComplete`

**Files**
- edit `Sources/VeloCore/Sync/BackfillService.swift`
- edit `Tests/VeloCoreTests/BackfillServiceTests.swift`

**Interfaces**
```swift
public struct BackfillService {
    public init(source: GmailReading, store: MailStore, syncState: SyncStateStore)
    public func backfillInbox(accountID: String, maxMessages: Int) async throws
}
```
Body order (**capture baseline BEFORE listing** to avoid a mid-backfill gap):
```
let baseline = try await source.getProfile().historyId
... existing listInboxMessageIDs paging -> prefix(maxMessages) -> getMessage each ...
try InboxReconciler.reconcile(dtos, into: store)
try syncState.save(SyncState(accountID: accountID, historyId: baseline, backfillComplete: true))
```
`SyncState` is saved **only after `reconcile` succeeds**.

Test double (`ScriptedSource`): add `let profileHistoryId: String` (default `"5000"`) and `var callLog: [String] = []`; each method appends its own name; `getProfile` returns `GmailProfile(emailAddress: "u@x.com", historyId: profileHistoryId)`. Test helper builds one `AppDatabase`, then `MailStore(db)` + `SyncStateStore(db)` sharing it.

**Test cases**
1. After `backfillInbox`, bind `let state = try syncStore.load(accountID:)`; `#expect state?.historyId == profileHistoryId` and `state?.backfillComplete == true`.
2. Baseline from `getProfile`, not message internalDates: `profileHistoryId "7777"` while messages carry `internalDate 1000/2000` → stored historyId `"7777"`.
3. `getProfile` invoked before `listInboxMessageIDs`: `source.callLog.first == "profile"` (bind `callLog` to a `let`).
4. Existing `reconcilesPagedMessagesIntoInbox` / `isIdempotentOnSecondRun` / `respectsMaxMessagesCap` keep passing after migrating to the new `init`/`backfillInbox` signature.
5. Re-running backfill overwrites `historyId` with a fresh baseline and keeps `backfillComplete == true` (the history-expired re-backfill path).

---

## Task A3 — History-expired recovery: `SyncError.historyExpired` + 404 detection

**Files**
- create `Sources/VeloCore/Sync/SyncError.swift`
- edit `Sources/VeloCore/Sync/IncrementalSyncService.swift`
- edit `Tests/VeloCoreTests/IncrementalSyncServiceTests.swift`

**Interfaces**
```swift
public enum SyncError: Error, Equatable {
    case notInitialized
    case historyExpired   // startHistoryId too old (Gmail 404); caller must re-backfill
}

// IncrementalSyncService.sync — wrap fetchHistory inside the paging loop:
do {
    page = try await source.fetchHistory(startHistoryId: startHistoryId, pageToken: pageToken)
} catch let error as AuthError where Self.isHistoryExpired(error) {
    throw SyncError.historyExpired   // throw BEFORE advancing cursor / saving SyncState
}

private static func isHistoryExpired(_ error: AuthError) -> Bool {
    guard case let .server(code, _) = error else { return false }
    return code == "404" || code == "NOT_FOUND"
}
```
Test double: add `ThrowingFetchHistorySource: GmailReading` whose `fetchHistory` throws a supplied error; `listInboxMessageIDs`/`getMessage`/`getProfile` → `fatalError`; track `getCallCount`. Keep it a `final class` (safe: tests run serially).

**Do NOT** change `checkedDecode`'s status-first mapping — `GmailAPIClientTests.nonSuccessMapsToServerError` asserts `code == "UNAUTHENTICATED"`. That is why the guard matches both `"404"` and `"NOT_FOUND"`.

**Test cases**
1. `fetchHistory` throwing `AuthError.server(code: "404", …)` → `await #expect(throws: SyncError.historyExpired) { try await service.sync(accountID:) }`.
2. `AuthError.server(code: "NOT_FOUND", …)` also → `SyncError.historyExpired`.
3. Cursor untouched on expiry: bind `let state = try syncStore.load(accountID:)` after the throw; `#expect state?.historyId == seed ("1000")`.
4. `getMessage` never called on expiry (`source.getCallCount == 0`).
5. Non-404 server error `AuthError.server(code: "UNAUTHENTICATED", description: "bad")` propagates unchanged (NOT mapped).
6. Existing `appliesAddedMessagesAndAdvancesCursor` / `pagesThroughHistory` / `isIdempotentOnSecondRun` / `throwsNotInitializedWhenNoCursor` stay green (and A1's `getProfile` stub on `HistorySource` remains).

---

# PHASE 2 — Increment B (outbound)

## Task B1 — Migration **v3** + `PendingMutation` record + enums

**Files**
- edit `Sources/VeloCore/Storage/AppDatabase.swift`
- create `Sources/VeloCore/Models/PendingMutation.swift`
- edit `Tests/VeloCoreTests/AppDatabaseTests.swift`
- create `Tests/VeloCoreTests/PendingMutationTests.swift`

**Interfaces**
```swift
public enum MutationKind: String, Codable, Equatable { case archive, markRead, markUnread } // send added later
public enum MutationStatus: String, Codable, Equatable { case pending, failed }

public struct PendingMutation: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    public var id: Int64?
    public var kind: MutationKind
    public var payload: Data                 // JSON-encoded OutboundMutationPayload
    public var createdAt: Date
    public var status: MutationStatus
    public static let databaseTableName = "pendingMutation"
    public init(id: Int64? = nil, kind: MutationKind, payload: Data,
                createdAt: Date, status: MutationStatus = .pending)
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// AppDatabase.migrator — append AFTER v2:
migrator.registerMigration("v3_create_pending_mutation") { db in
    try db.create(table: "pendingMutation") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("kind", .text).notNull()
        t.column("payload", .blob).notNull()
        t.column("createdAt", .datetime).notNull()
        t.column("status", .text).notNull().defaults(to: "pending")
    }
    try db.create(index: "pendingMutation_on_status", on: "pendingMutation", columns: ["status"])
}
```
**GRDB note:** this is the FIRST autoincrement record in the package — conform to `MutablePersistableRecord` (NOT `PersistableRecord`), `var id: Int64? = nil`, implement `didInsert`. Do NOT conform to `Identifiable`.

**Test cases**
1. `AppDatabaseTests`: in-memory DB has table `pendingMutation` — read `db.tableExists("pendingMutation")` into a `let` inside the read block, `#expect` true (keep existing thread/message asserts).
2. Inserting `PendingMutation(id: nil, …)` assigns an autoincrement id — insert a `var`, read `m.id` into a local, `#expect` it equals `1` for the first row.
3. Round-trip: insert, `fetchOne` by id into a local, `#expect` kind/status/payload bytes/`createdAt` (compare via `timeIntervalSince1970`) equal what was inserted.
4. Enum raw-string storage: read raw `kind`/`status` text via `Row`, `#expect` `"archive"` and `"pending"`.
5. Two sequential inserts get ascending ids (FIFO by id).

---

## Task B2 — `MutationStore`

**Files**
- create `Sources/VeloCore/Storage/MutationStore.swift`
- create `Tests/VeloCoreTests/MutationStoreTests.swift`

**Interfaces**
```swift
public final class MutationStore {
    public init(_ database: AppDatabase)
    public func enqueue(_ mutation: PendingMutation) throws -> PendingMutation  // returns row with id populated
    public func pending() throws -> [PendingMutation]  // status == .pending, ordered by id asc (FIFO)
    public func markFailed(id: Int64) throws           // fetch-mutate-update, mirrors MailStore.setLabels
    public func delete(id: Int64) throws               // removes the row — models 'done' (no done status)
    public func all() throws -> [PendingMutation]       // all rows, id asc
}
```
`enqueue` does `var m = mutation; try m.insert(db); return m` inside `dbQueue.write`. Filter with `Column("status") == MutationStatus.pending.rawValue`.

**Test cases**
1. `enqueue` returns a mutation whose `id != nil`.
2. `pending()` returns only `.pending` rows FIFO — enqueue three, `markFailed` the middle, `#expect` `pending().map(\.id)` equals first+third in insertion order.
3. `markFailed` excludes from `pending()` but keeps it in `all()` as `.failed`.
4. `delete` removes the row (`all()` empty).
5. `enqueue` preserves order across calls — `pending().map(\.id)` strictly ascending.
6. `markFailed`/`delete` on an unknown id is a safe no-op (no throw, `all().count` unchanged).

---

## Task B3 — `GmailWriting` seam + `GmailAPIClient.modifyMessage`

**Files**
- edit `Sources/VeloCore/Sync/GmailAPIClient.swift`
- create `Tests/VeloCoreTests/GmailAPIClientWriteTests.swift`

**Interfaces**
```swift
// Declared inline adjacent to GmailReading:
public protocol GmailWriting {
    func modifyMessage(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessageDTO
}
extension GmailAPIClient: GmailWriting { }   // struct now conforms to GmailReading, GmailWriting

public func modifyMessage(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessageDTO {
    let url = baseURL.appendingPathComponent("users/me/messages/\(id)/modify")
    let body = try JSONEncoder().encode(ModifyRequest(addLabelIds: addLabelIDs, removeLabelIds: removeLabelIDs))
    let (data, response) = try await authorizedPOST(url, body: body)
    return try checkedDecode(data, response)
}
private struct ModifyRequest: Encodable { let addLabelIds: [String]; let removeLabelIds: [String] }

private func authorizedPOST(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
    let token = try await tokenProvider.validAccessToken()
    do {
        return try await httpClient.post(url: url,
            headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"], body: body)
    } catch { throw AuthError.network(error) }
}
```
**Gmail shape:** `POST users/me/messages/{id}/modify`, body `{"addLabelIds":[…],"removeLabelIds":[…]}`, **Content-Type `application/json`** (unlike TokenService's form-encoding). Response is an updated message resource DTO. Modify is idempotent (removing INBOX twice is a no-op).

**Test cases** (new post-recording `MockHTTPClient` records `lastPostURL/lastPostHeaders/lastPostBody`, `get()` fatalErrors)
1. `modifyMessage(id:"m1", add:[], remove:["INBOX"])` → URL ends `/messages/m1/modify`; decoded body has `addLabelIds == []`, `removeLabelIds == ["INBOX"]`.
2. Headers: `Authorization == "Bearer tok"`, `Content-Type == "application/json"`.
3. Parses updated resource — response DTO whose `labelIds` omit INBOX; `#expect` `dto.id`/`dto.labelIds` reflect response.
4. Non-2xx maps: 403 `{"error":{"code":403,"status":"PERMISSION_DENIED"}}` → `await #expect(throws: AuthError.server(code: "PERMISSION_DENIED", …))`.
5. Transport failure → `MockHTTPClient.post` returns `.failure(Boom())` → `await #expect(throws: AuthError.network(…))`.

---

## Task B4 — `OutboundService` optimistic apply + `MailStore.thread(id:)`

**Files**
- edit `Sources/VeloCore/Storage/MailStore.swift`
- create `Sources/VeloCore/Sync/OutboundService.swift`
- edit `Tests/VeloCoreTests/MailStoreTests.swift`
- create `Tests/VeloCoreTests/OutboundServiceTests.swift`

**Interfaces**
```swift
// MailStore:
public func thread(id: String) throws -> MailThread?   // dbQueue.read { try MailThread.fetchOne($0, key: id) }

// Internal payload persisted in PendingMutation.payload (tests use @testable import):
struct OutboundMutationPayload: Codable, Equatable {
    var threadID: String
    var messageIDs: [String]
    var addLabelIDs: [String]
    var removeLabelIDs: [String]
    var previousLabelIDs: [String]
    var previousIsUnread: Bool
}

public struct OutboundService {
    public init(writer: GmailWriting, store: MailStore, mutations: MutationStore,
                now: @escaping () -> Date = { Date() })   // NO @Sendable, matches TokenService style
    public func archive(threadID: String) throws     // remove:["INBOX"], add:[]
    public func markRead(threadID: String) throws     // remove:["UNREAD"], add:[]
    public func markUnread(threadID: String) throws   // remove:[], add:["UNREAD"]
}
// private enqueueLabelChange(threadID:kind:add:remove:):
//   guard let thread = store.thread(id:) else { return }
//   messageIDs = store.messages(inThread:).map(\.id); capture previousLabelIDs/previousIsUnread
//   newLabels = thread.labelIDs.filter { !remove.contains($0) } + adds not already present
//   var updated = thread; updated.labelIDs = newLabels; updated.isUnread = newLabels.contains("UNREAD"); store.upsert(updated)
//   mutations.enqueue(PendingMutation(kind:, payload: JSONEncoder().encode(payload), createdAt: now(), status: .pending))
```
Optimistic apply is **thread-level**; the payload carries every message id for drain to iterate.

**Test cases**
1. `MailStoreTests`: `thread(id:)` returns stored thread or nil.
2. `archive` removes INBOX locally + enqueues one `.archive`; decoded payload `removeLabelIDs == ["INBOX"]`, `addLabelIDs == []`, `messageIDs` = thread's message ids, `previousLabelIDs` contains `"INBOX"`; thread gone from `inboxThreads()`.
3. `markRead` clears unread locally + enqueues `.markRead` (`removeLabelIDs == ["UNREAD"]`).
4. `markUnread` sets unread locally + enqueues `.markUnread` (`addLabelIDs == ["UNREAD"]`).
5. `archive` preserves unread flag (thread `["INBOX","UNREAD"]` → still unread, only INBOX removed).
6. Unknown threadID is a no-op (`pending().count == 0`, no rows changed).
7. `createdAt` uses injected `now` — construct with `now: { fixedDate }`, `#expect` enqueued `createdAt == fixedDate`.

---

## Task B5 — `OutboundService.drain` (idempotent; revert + markFailed on failure)

**Files**
- edit `Sources/VeloCore/Sync/OutboundService.swift`
- edit `Tests/VeloCoreTests/OutboundServiceTests.swift`

**Interfaces**
```swift
extension OutboundService {
    /// Drains all pending mutations. For each: modifyMessage for every payload.messageID with its add/remove labels;
    /// on success delete the mutation; on API failure revert the thread to previousLabelIDs/previousIsUnread
    /// (via store.upsert) and markFailed(id:), then continue. Discards the returned DTO. Throws only on genuine
    /// DB/decode faults, never on an API failure.
    public func drain() async throws
}
```
Rules: revert is driven **entirely from the persisted payload** (drain may run in a later process). Use `guard let id = mutation.id else { continue }` — never force-unwrap. Success = `delete(id:)`; API failure = revert + `markFailed(id:)` + continue (do NOT rethrow API errors). Lean on Gmail modify idempotency for crash-between-apply-and-delete safety.

Test double: `private final class ScriptedWriter: GmailWriting { var failingMessageIDs: Set<String>; private(set) var modifyCalls: [(id,add,remove)]; ... throws AuthError.server(code:"500",…) for failing ids, else returns a decoded DTO }`.

**Test cases**
1. Drain success modifies every message then deletes the row — 2-message archive; `modifyCalls` once per message id with `removeLabelIDs ["INBOX"]`; queue empty; thread stays archived.
2. Drain failure reverts + marks failed — writer throws for one message id; thread restored to `previousLabelIDs` (back in inbox) + `previousIsUnread`; mutation in `all()` `.failed`; `pending()` empty.
3. Drain idempotent after success — drain to empty, reset `modifyCalls`, drain again → no new calls, queue stays empty.
4. Re-drain after already-applied modify still succeeds (writer returns success) → row deleted.
5. Drain processes multiple queued mutations — two archives over two threads emptied in one drain.
6. A failed mutation does not block a good one — `archive(threadA)` failing + `archive(threadB)` succeeding → threadA `.failed`+reverted, threadB deleted+archived.

---

# PHASE 3 — Increment C (per-message labels)

## Task C1 — Migration **v4** + `Message.labelIDs` (+ fix call sites)

**Files**
- edit `Sources/VeloCore/Storage/AppDatabase.swift`
- edit `Sources/VeloCore/Models/Message.swift`
- edit `Tests/VeloCoreTests/ModelCodingTests.swift`, `MailStoreTests.swift`, `AppDatabaseTests.swift`

**Interfaces**
```swift
// AppDatabase.migrator — append AFTER v3 (B already took v3 → this is v4):
migrator.registerMigration("v4_add_message_labelIDs") { db in
    try db.alter(table: "message") { t in
        t.add(column: "labelIDs", .text).notNull().defaults(to: "[]")
    }
}

// Message: add stored field + extend init (labelIDs LAST, NO default, matching MailThread.init convention):
public var labelIDs: [String]
public init(id:threadID:sender:recipients:subject:date:bodyHTML:bodyText:isUnread:labelIDs:[String])
```
**Breaks 4 call sites — update in the same change:** `Sources/VeloCore/Sync/GmailMessageMapper.swift:22`, `Tests/VeloCoreTests/MailStoreTests.swift:38` and `:41`, `Tests/VeloCoreTests/ModelCodingTests.swift:26`. GRDB stores `[String]` as JSON text via Codable; `'[]'` default backfills existing rows.

**Test cases**
1. `message` table has a `labelIDs` column after migration — assert by column presence (`db.columns(in:"message")`), **not** version number.
2. Rows default `labelIDs` to `[]` when unspecified in the source data path.
3. `Message` round-trips through GRDB with populated `labelIDs` (e.g. `["INBOX","UNREAD"]`) — extend `ModelCodingTests.messageRoundTrips`.
4. All pre-existing MailStore/ModelCoding tests compile and pass with the new required init param.

---

## Task C2 — Mapper populates `message.labelIDs` + aggregates thread labels

**Files**
- edit `Sources/VeloCore/Sync/GmailMessageMapper.swift`
- edit `Tests/VeloCoreTests/GmailMessageMapperTests.swift`

**Interfaces**
```swift
// message(from:) sets labelIDs: dto.labelIds ?? []
public static func threadAggregate(from messages: [Message]) -> (labelIDs: [String], isUnread: Bool)
//   labelIDs = Set(messages.flatMap { $0.labelIDs }).sorted()
//   isUnread = messages.contains { $0.labelIDs.contains("UNREAD") }
// Refactor thread(from dtos:) to compute labelIDs/isUnread via threadAggregate over dtos.map(message(from:)),
// keeping snippet/lastMessageDate/hasAttachments from DTOs → one shared code path for backfill + delta re-derive.
```

**Test cases**
1. `message(from:)` copies `dto.labelIds` into `Message.labelIDs`; `[]` when nil.
2. `threadAggregate` unions labelIDs across messages, sorted.
3. `threadAggregate.isUnread` true iff any message has `"UNREAD"`.
4. `threadAggregate(from: [])` → `([], false)`.
5. Existing `derivesThreadFromMultipleMessages` still passes (`labelIDs == ["INBOX","UNREAD"]`, `isUnread == true`) — proves the refactor is behavior-preserving.

---

## Task C3 — Decode `labelsAdded`/`labelsRemoved` + request them from the API

**Files**
- edit `Sources/VeloCore/Sync/GmailHistoryResponse.swift`
- edit `Sources/VeloCore/Sync/GmailAPIClient.swift`
- edit `Tests/VeloCoreTests/GmailHistoryResponseTests.swift`, `GmailAPIClientTests.swift`

**Interfaces**
```swift
// GmailHistoryResponse.Record:
public let labelsAdded: [LabelChange]?
public let labelsRemoved: [LabelChange]?
public struct LabelChange: Decodable, Equatable { public let message: Added.Ref; public let labelIds: [String]? }

public struct LabelDelta: Equatable { public let messageID: String; public let added: [String]; public let removed: [String] }
// Flatten records IN ORDER: per labelsAdded entry emit LabelDelta(added: entry.labelIds ?? [], removed: []),
// per labelsRemoved entry emit LabelDelta(added: [], removed: entry.labelIds ?? []). addedMessageIDs unchanged.
public var labelDeltas: [LabelDelta]

// GmailAPIClient.fetchHistory: append repeated query items
//   historyTypes=messageAdded, historyTypes=labelAdded, historyTypes=labelRemoved
```
**Gmail shape:** history `messages[].labelsAdded[].{message:{id},labelIds:[…]}` and `labelsRemoved[]…`. Gmail omits label history unless `historyTypes=labelAdded`/`labelRemoved` are requested (multiple `historyTypes` params allowed). **Do NOT collapse into two aggregate added/removed sets** — cross-record order must be preserved.

**Test cases**
1. Decodes `labelsAdded`/`labelsRemoved`, exposes `labelDeltas` with correct `messageID`/`added`/`removed`.
2. Cross-record order preserved: record1 `labelsRemoved [UNREAD]` then record2 `labelsAdded [UNREAD]` appear in that order.
3. Record with only `labelsRemoved` → single remove delta, `addedMessageIDs == []` (extend `recordWithoutMessagesAddedContributesNothing`).
4. Empty/absent history → `labelDeltas == []` and `addedMessageIDs == []`.
5. `fetchHistory` query contains `historyTypes=labelAdded` + `labelRemoved` (and still `messageAdded`) with bearer attached.

---

## Task C4 — `LabelDeltaApplier` + MailStore accessors

**Files**
- edit `Sources/VeloCore/Storage/MailStore.swift`
- create `Sources/VeloCore/Sync/LabelDeltaApplier.swift`
- edit `Tests/VeloCoreTests/MailStoreTests.swift`
- create `Tests/VeloCoreTests/LabelDeltaApplierTests.swift`

**Interfaces**
```swift
// MailStore:
public func message(id: String) throws -> Message?    // Message.fetchOne(key: id)
public func updateThreadDerivedLabels(_ labelIDs: [String], isUnread: Bool, onThread threadID: String) throws
//   single write: fetchOne thread; set labelIDs + isUnread; update — PRESERVE snippet/date/hasAttachments; no-op if absent

public enum LabelDeltaApplier {
    public static func apply(_ deltas: [GmailHistoryResponse.LabelDelta], into store: MailStore) throws
}
// iterate deltas IN ORDER: load store.message(id:) (skip if nil);
//   labelIDs = Set(labelIDs).subtracting(removed).union(added).sorted(); isUnread = labelIDs.contains("UNREAD");
//   upsert message; record threadID.
// then per affected threadID: messages = store.messages(inThread:);
//   (labels, unread) = GmailMessageMapper.threadAggregate(from: messages);
//   store.updateThreadDerivedLabels(labels, isUnread: unread, onThread: threadID)
```
**Layering:** orchestration lives in Sync-layer `LabelDeltaApplier`, calling MailStore primitives + the mapper aggregate — do not import the mapper into the Storage layer.

**Test cases**
1. `MailStore.message(id:)` returns record for known id, nil for unknown.
2. `updateThreadDerivedLabels` updates labelIDs+isUnread, leaves snippet/lastMessageDate/hasAttachments unchanged; no-op when thread absent.
3. `removed:[UNREAD]` on a thread's only message clears message.isUnread + labelIDs, re-derives thread `isUnread == false` / no UNREAD.
4. `removed:[INBOX]` on every message archives the thread out of `inboxThreads()`.
5. Two-message thread: removing UNREAD from one keeps `thread.isUnread == true` (any-unread aggregate).
6. `added:[Label_9]` unions the label into message + thread labelIDs (sorted).
7. Delta for unknown message id is a no-op (no thread touched, no throw).
8. Ordered deltas record1 remove UNREAD then record2 add UNREAD net to UNREAD present.

---

## Task C5 — IncrementalSyncService applies label deltas end-to-end

**Files**
- edit `Sources/VeloCore/Sync/IncrementalSyncService.swift`
- edit `Tests/VeloCoreTests/IncrementalSyncServiceTests.swift`

**Interfaces**
```swift
// sync(accountID:): while paging, accumulate var labelDeltas: [GmailHistoryResponse.LabelDelta]
//   by appending page.labelDeltas alongside page.addedMessageIDs (preserve order).
// After InboxReconciler.reconcile(dtos, into: store):
//   try LabelDeltaApplier.apply(labelDeltas, into: store)
//   then advance/save the cursor as today.
// Reconcile messagesAdded FIRST, then apply deltas (freshly-arrived messages exist before deltas that target them).
```
This edit stacks on A3's do/catch (already present in this file). Extend the test-file `historyPage(...)` helper to optionally embed `labelsAdded`/`labelsRemoved` in the JSON fixture.

**Test cases**
1. A message stored from a prior run gets `labelsRemoved [UNREAD]` via history → message + parent thread become read; cursor advances to the page historyId.
2. `labelsRemoved [INBOX]` on a stored thread's messages removes it from `inboxThreads()`; cursor advances.
3. `messagesAdded` + `labelsAdded` on a different stored message in one sync → new message lands with hydrated labels AND the stored message gains the label; second sync (empty history) idempotent.
4. Delta-only page (no `messagesAdded`) still applies deltas and advances the cursor without calling `getMessage` (`getCallCount == 0`).
5. A `labelsAdded/Removed` for a message not present locally is ignored, does not throw; cursor still advances.

---

# PHASE 4 — Increment D (GmailSync actor)

## Task D1 — Make sync collaborators `Sendable`

**Files**
- edit `AppDatabase.swift`, `MailStore.swift`, `SyncStateStore.swift`, `GmailAPIClient.swift`, `BackfillService.swift`, `IncrementalSyncService.swift`
- edit `Tests/VeloCoreTests/BackfillServiceTests.swift`, `IncrementalSyncServiceTests.swift`
- create `Tests/VeloCoreTests/SendableConformanceTests.swift`

**Interfaces / conformances**
```swift
public final class AppDatabase: Sendable          // single immutable let dbQueue (GRDB @unchecked Sendable)
public final class MailStore: Sendable
public final class SyncStateStore: Sendable
public protocol GmailReading: Sendable { /* getProfile/listInboxMessageIDs/getMessage/fetchHistory unchanged */ }
public struct BackfillService: Sendable
public struct IncrementalSyncService: Sendable
public struct GmailAPIClient: GmailReading, @unchecked Sendable
//   documented: holds URL + HTTPClient + AccessTokenProvider, only ever driven from the serialized actor,
//   so token-refresh writes never race — full Auth-layer Sendable pass deferred.
```
Annotate scripted `final class ScriptedSource`/`HistorySource` doubles `@unchecked Sendable`. **Do NOT bump swift-tools-version (5.9 / Swift 5 language mode on a 6.1 toolchain)** — strict-concurrency issues surface as warnings, but design for correctness anyway. GRDB's `DatabaseQueue` is `@unchecked Sendable` (verified at `.build/checkouts/GRDB.swift/…/DatabaseQueue.swift:127`).

**Test cases**
1. `SendableConformanceTests`: `func requireSendable<T: Sendable>(_ v: T) {}` called with `let`-extracted instances of `MailStore`, `SyncStateStore`, `BackfillService`, `IncrementalSyncService` — compile-time guard that fails to build if any lost `Sendable`.
2. Existing `BackfillServiceTests` green after `ScriptedSource` annotated (run full suite).
3. Existing `IncrementalSyncServiceTests` green after `HistorySource` annotated.

---

## Task D2 — TDD the `GmailSync` actor

**Files**
- create `Sources/VeloCore/Sync/GmailSync.swift`
- create `Tests/VeloCoreTests/GmailSyncTests.swift`

**Interfaces**
```swift
public actor GmailSync {
    public init(accountID: String, backfill: BackfillService, incremental: IncrementalSyncService,
                outbound: OutboundService, syncState: SyncStateStore, backfillLimit: Int = 500)
    /// One initial sync pass; real scheduling/polling intentionally deferred.
    public func start() async throws
    /// One serialized pass: load sync_state; run backfill only when backfillComplete != true;
    /// then incremental.sync(accountID:); then outbound drain. Overlapping calls coalesced.
    public func syncNow() async throws

    private var isSyncing = false
    // syncNow: guard !isSyncing else { return }; isSyncing = true BEFORE the first await
    // (actor runs synchronously up to first suspension); clear in defer.
}
```
**Reconciliation with Increment B:** D's design assumed `outbound.processPending(accountID:)`; B's **actual** API is `OutboundService.drain() async throws` (no accountID). The last step is `try await outbound.drain()`. Update the D test that inspects the drained queue accordingly.

**Pass order:** `load sync_state` → `if state?.backfillComplete != true { backfill.backfillInbox(accountID:, maxMessages: backfillLimit) }` → `incremental.sync(accountID:)` → `outbound.drain()`. Backfill (A) must establish `historyId` + `backfillComplete` before incremental, else incremental throws `SyncError.notInitialized`.

**Out of scope for D (explicit):** no timers, polling, on-focus refresh, or offline backoff. `start()` is just one `syncNow()`. A future enhancement may reset `backfillComplete` on a `SyncError.historyExpired` (C/A surface) to force re-backfill — deferred to keep D deterministic.

**Test cases**
1. Fresh account (no sync_state row): real Backfill+Incremental over one shared scripted `GmailReading` + in-memory `AppDatabase`, plus real `OutboundService` over a scripted writer with one seeded pending_mutation. Call `syncNow()`; `let threads = try mailStore.inboxThreads()` → backfilled + incremental threads present; `let state = try syncStore.load(accountID:)` → `backfillComplete == true`, `historyId` equals scripted history id; seeded mutation drained (row removed). [depends A+B]
2. Already-backfilled account: seed `SyncState(backfillComplete: true, historyId: "1000")`; `syncNow()` → scripted `listInboxMessageIDs` call count `== 0` (backfill skipped) while `fetchHistory` ran and cursor advanced.
3. Orchestration order: shared scripted source appends each call to a log; after `syncNow()` on a fresh account, `let log = source.callLog` → every `listInboxMessageIDs` entry precedes every `fetchHistory` entry, and outbound drain recorded after incremental.
4. Reentrancy coalescing: `async let a = sync.syncNow(); async let b = sync.syncNow(); _ = try await (a, b)` → `listInboxMessageIDs` invoked exactly once (isSyncing guard prevents a second overlapping backfill).
5. `start()` on a fresh account produces the same effects as case 1.
6. Error propagation: scripted source throwing on `getMessage` makes `syncNow()` rethrow — `await #expect(throws:) { try await sync.syncNow() }`; then a subsequent `syncNow()` still runs (proves the `defer` cleared `isSyncing`).
7. Incremental precondition guard: on the fresh-account case, backfill (A) establishes the cursor so incremental does not throw `SyncError.notInitialized` — successful completion documents D's reliance on A running first.

---

# Cross-cutting rules (apply to every task)

- **Test-style constraint (repo-wide):** never write `#expect(try someThrowingCall())`. Bind the throwing call to a local `let` first (e.g. `let state = try syncStore.load(...)`), then `#expect` on the value. Use `await #expect(throws:) { try await … }` for throwing expectations. Existing suites predate this rule — do not copy their inline `try`; new/edited tests must comply.
- **`historyId` is a `String` end-to-end** (Gmail sends it quoted in both profile and history payloads). Never parse to `Int`.
- **checkedDecode status-first mapping is frozen:** a 404 surfaces as code `"NOT_FOUND"`; a 401 as `"UNAUTHENTICATED"`. `GmailAPIClientTests.nonSuccessMapsToServerError` asserts this — the history-expired guard matches both `"404"` and `"NOT_FOUND"` rather than changing the decoder.
- **Persist state only after success:** BackfillService saves `SyncState` only after `reconcile`; `drain()` deletes only after every per-message modify succeeds; IncrementalSyncService advances the cursor only after reconcile + delta apply.
- **Swift 6 concurrency:** structs with async methods + scripted (non-`Sendable`) test doubles reused within a single serial test; `now` is `@escaping () -> Date` **without** `@Sendable`. The actor sets `isSyncing = true` before the first `await` and clears it in `defer`. Do not bump swift-tools-version.
- **Gmail request/response shapes used:**
  - `GET users/me/profile` → `{emailAddress, historyId(string), messagesTotal?, threadsTotal?}` (A).
  - `POST users/me/messages/{id}/modify` body `{addLabelIds, removeLabelIds}`, Content-Type `application/json`, returns updated message resource; idempotent (B).
  - `history.list` with `historyTypes=messageAdded&historyTypes=labelAdded&historyTypes=labelRemoved`; records carry `labelsAdded[]`/`labelsRemoved[]` as `{message:{id}, labelIds:[…]}` (C).
  - `users/me/messages/send` (RFC 2822 raw) — **explicitly deferred** to a follow-up increment depending on B; `MutationKind.send` intentionally omitted now.

# Explicitly OUT of scope (and why)

- **GUI / interactive sign-in / any UI.** Every increment is headless and testable with scripted mocks + in-memory `AppDatabase`; the package surface is services and stores only.
- **Real OAuth credentials / live token acquisition.** Tests inject a token provider that returns `"tok"`; `GmailAPIClient` is only exercised via a `MockHTTPClient`. No real network, no secrets. (`GmailAPIClient` is `@unchecked Sendable` precisely to avoid dragging the live Auth stack — HTTPClient/AccessTokenProvider/TokenService/TokenStore — into strict-concurrency scope here.)
- **Send path** (`MutationKind.send`, RFC 2822 raw, `messages/send`) — deferred to a later increment that depends on B.
- **Per-message label reconcile from modify responses** — `drain()` discards the returned DTO; folding per-message deltas back stays deferred (same deferral IncrementalSyncService already makes).
- **Timers, polling, on-focus refresh, offline backoff, and history-expired auto-re-backfill wiring** — out of D; `start()` is a single `syncNow()`. Re-backfill policy on `SyncError.historyExpired` belongs to a future scheduler.
- **Hydrating label-only new-to-inbox messages** (a `labelsAdded` for a message backfill never fetched) — C skips unknown message ids by design; hydration is a noted known limitation.
