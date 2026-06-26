# VeloCore Storage Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `VeloCore`, a testable Swift Package providing the local-first storage layer (SQLite via GRDB) that is the source of truth for Velo Mail's inbox.

**Architecture:** A standalone Swift Package with one library target (`VeloCore`) and a test target. Storage uses a GRDB `DatabaseQueue` with a versioned `DatabaseMigrator`. Domain models (`MailThread`, `Message`, `Label`) are GRDB records. `MailStore` is the public read/write API; reactive reads use GRDB `ValueObservation`. The UI (future) and sync engine (future) both depend only on `MailStore`.

**Tech Stack:** Swift 6.1 (Swift 5 language mode), Swift Package Manager, GRDB.swift, Swift Testing (`import Testing`). Builds/tests with Command Line Tools only — no Xcode app required.

> **Note (added during execution):** Command Line Tools (no Xcode.app) does **not** ship `XCTest`, but **does** ship Swift Testing. All tests use Swift Testing (`@Suite` / `@Test` / `#expect`), not `XCTest`. If Xcode.app is installed later, XCTest becomes available but there is no need to migrate.

## Global Constraints

- Swift tools version: `5.9` (avoid Swift 6 strict-concurrency churn for now).
- Platform floor: macOS 14 (`.macOS(.v14)` in `Package.swift`).
- Dependency: GRDB.swift, `from: "6.29.0"`. No other third-party deps in this plan.
- The model type for an email thread is named **`MailThread`** (NOT `Thread` — that collides with `Foundation.Thread`).
- Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`, `Issue.record`) — NOT XCTest (unavailable under Command Line Tools).
- Tests use in-memory databases (`DatabaseQueue()` with no path). No file I/O or network in tests.
- All code lives under `/Users/dedemahendra/Developer/Projects/VeloMail`.
- Commit after every task with the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.

---

### Task 1: Swift Package skeleton with GRDB

**Files:**
- Create: `Package.swift`
- Create: `Sources/VeloCore/VeloCore.swift`
- Create: `Tests/VeloCoreTests/VeloCoreTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable package named `VeloCore` with GRDB linked; an empty namespace enum `VeloCore`.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VeloCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VeloCore", targets: ["VeloCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "VeloCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
    ]
)
```

- [ ] **Step 2: Write the namespace placeholder**

`Sources/VeloCore/VeloCore.swift`:
```swift
/// Namespace for the Velo Mail core library.
public enum VeloCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Write a smoke test**

`Tests/VeloCoreTests/VeloCoreTests.swift`:
```swift
import Testing
@testable import VeloCore

@Test func testVersionIsSet() {
    #expect(VeloCore.version == "0.1.0")
}
```

- [ ] **Step 4: Write `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj
.DS_Store
```

- [ ] **Step 5: Resolve and run tests**

Run: `cd /Users/dedemahendra/Developer/Projects/VeloMail && swift test`
Expected: GRDB downloads/resolves; build succeeds; `testVersionIsSet` PASSES.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources Tests .gitignore
git commit -m "feat: scaffold VeloCore package with GRDB"
```

---

### Task 2: Database setup and migrations

**Files:**
- Create: `Sources/VeloCore/Storage/AppDatabase.swift`
- Test: `Tests/VeloCoreTests/AppDatabaseTests.swift`

**Interfaces:**
- Consumes: GRDB.
- Produces:
  - `final class AppDatabase` with:
    - `init(_ dbQueue: DatabaseQueue) throws` — runs migrations.
    - `static func makeInMemory() throws -> AppDatabase` — for tests.
    - `static func make(atPath path: String) throws -> AppDatabase` — for the app.
    - `let dbQueue: DatabaseQueue` (internal access for store).
  - Schema after migration: tables `thread` and `message` (columns defined below).

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/AppDatabaseTests.swift`:
```swift
import Testing
import GRDB
@testable import VeloCore

@Suite struct AppDatabaseTests {
    @Test func migrationsCreateTables() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            #expect(try db.tableExists("thread"))
            #expect(try db.tableExists("message"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppDatabaseTests`
Expected: FAIL — `AppDatabase` not found.

- [ ] **Step 3: Implement `AppDatabase`**

`Sources/VeloCore/Storage/AppDatabase.swift`:
```swift
import Foundation
import GRDB

/// Owns the SQLite connection and applies schema migrations.
public final class AppDatabase {
    public let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    public static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue())
    }

    public static func make(atPath path: String) throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue(path: path))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_thread_and_message") { db in
            try db.create(table: "thread") { t in
                t.primaryKey("id", .text)
                t.column("snippet", .text).notNull().defaults(to: "")
                t.column("lastMessageDate", .datetime).notNull()
                t.column("isUnread", .boolean).notNull().defaults(to: false)
                t.column("hasAttachments", .boolean).notNull().defaults(to: false)
                t.column("labelIDs", .text).notNull().defaults(to: "[]")
            }

            try db.create(table: "message") { t in
                t.primaryKey("id", .text)
                t.column("threadID", .text).notNull()
                    .references("thread", onDelete: .cascade)
                t.column("sender", .text).notNull().defaults(to: "")
                t.column("recipients", .text).notNull().defaults(to: "[]")
                t.column("subject", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("bodyHTML", .text)
                t.column("bodyText", .text)
                t.column("isUnread", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "message_on_threadID", on: "message", columns: ["threadID"])
        }

        return migrator
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppDatabaseTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Storage/AppDatabase.swift Tests/VeloCoreTests/AppDatabaseTests.swift
git commit -m "feat: add AppDatabase with thread/message migrations"
```

---

### Task 3: Domain models

**Files:**
- Create: `Sources/VeloCore/Models/MailThread.swift`
- Create: `Sources/VeloCore/Models/Message.swift`
- Test: `Tests/VeloCoreTests/ModelCodingTests.swift`

**Interfaces:**
- Consumes: GRDB.
- Produces:
  - `struct MailThread: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable`
    with `id: String, snippet: String, lastMessageDate: Date, isUnread: Bool, hasAttachments: Bool, labelIDs: [String]`. Table name `"thread"`.
  - `struct Message: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable`
    with `id: String, threadID: String, sender: String, recipients: [String], subject: String, date: Date, bodyHTML: String?, bodyText: String?, isUnread: Bool`. Table name `"message"`.
  - GRDB stores `labelIDs` / `recipients` (`[String]`) as JSON text automatically (Codable arrays).

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/ModelCodingTests.swift`:
```swift
import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct ModelCodingTests {
    @Test func threadRoundTripsWithLabelArray() throws {
        let db = try AppDatabase.makeInMemory()
        let thread = MailThread(
            id: "t1", snippet: "hello",
            lastMessageDate: Date(timeIntervalSince1970: 1000),
            isUnread: true, hasAttachments: false,
            labelIDs: ["INBOX", "Label_5"]
        )
        try db.dbQueue.write { try thread.insert($0) }
        let fetched = try db.dbQueue.read { try MailThread.fetchOne($0, key: "t1") }
        #expect(fetched == thread)
        #expect(fetched?.labelIDs == ["INBOX", "Label_5"])
    }

    @Test func messageRoundTrips() throws {
        let db = try AppDatabase.makeInMemory()
        let thread = MailThread(id: "t1", snippet: "", lastMessageDate: Date(timeIntervalSince1970: 0),
                                isUnread: false, hasAttachments: false, labelIDs: [])
        try db.dbQueue.write { try thread.insert($0) }
        let msg = Message(
            id: "m1", threadID: "t1", sender: "a@b.com",
            recipients: ["c@d.com"], subject: "hi",
            date: Date(timeIntervalSince1970: 10),
            bodyHTML: "<p>hi</p>", bodyText: "hi", isUnread: true
        )
        try db.dbQueue.write { try msg.insert($0) }
        let fetched = try db.dbQueue.read { try Message.fetchOne($0, key: "m1") }
        #expect(fetched == msg)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelCodingTests`
Expected: FAIL — `MailThread` / `Message` not found.

- [ ] **Step 3: Implement `MailThread`**

`Sources/VeloCore/Models/MailThread.swift`:
```swift
import Foundation
import GRDB

public struct MailThread: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: String
    public var snippet: String
    public var lastMessageDate: Date
    public var isUnread: Bool
    public var hasAttachments: Bool
    public var labelIDs: [String]

    public static let databaseTableName = "thread"

    public init(id: String, snippet: String, lastMessageDate: Date,
                isUnread: Bool, hasAttachments: Bool, labelIDs: [String]) {
        self.id = id
        self.snippet = snippet
        self.lastMessageDate = lastMessageDate
        self.isUnread = isUnread
        self.hasAttachments = hasAttachments
        self.labelIDs = labelIDs
    }
}
```

- [ ] **Step 4: Implement `Message`**

`Sources/VeloCore/Models/Message.swift`:
```swift
import Foundation
import GRDB

public struct Message: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: String
    public var threadID: String
    public var sender: String
    public var recipients: [String]
    public var subject: String
    public var date: Date
    public var bodyHTML: String?
    public var bodyText: String?
    public var isUnread: Bool

    public static let databaseTableName = "message"

    public init(id: String, threadID: String, sender: String, recipients: [String],
                subject: String, date: Date, bodyHTML: String?, bodyText: String?, isUnread: Bool) {
        self.id = id
        self.threadID = threadID
        self.sender = sender
        self.recipients = recipients
        self.subject = subject
        self.date = date
        self.bodyHTML = bodyHTML
        self.bodyText = bodyText
        self.isUnread = isUnread
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ModelCodingTests`
Expected: PASS (both tests). If `labelIDs`/`recipients` fail to decode, confirm GRDB is encoding arrays as JSON — they should round-trip as shown.

- [ ] **Step 6: Commit**

```bash
git add Sources/VeloCore/Models Tests/VeloCoreTests/ModelCodingTests.swift
git commit -m "feat: add MailThread and Message GRDB models"
```

---

### Task 4: MailStore write + read API

**Files:**
- Create: `Sources/VeloCore/Storage/MailStore.swift`
- Test: `Tests/VeloCoreTests/MailStoreTests.swift`

**Interfaces:**
- Consumes: `AppDatabase`, `MailThread`, `Message`.
- Produces:
  - `public final class MailStore`
    - `init(_ database: AppDatabase)`
    - `func upsert(_ thread: MailThread) throws`
    - `func upsert(_ message: Message) throws`
    - `func inboxThreads() throws -> [MailThread]` — threads whose `labelIDs` contain `"INBOX"`, ordered by `lastMessageDate` descending.
    - `func messages(inThread threadID: String) throws -> [Message]` — ordered by `date` ascending.
    - `func setLabels(_ labelIDs: [String], onThread threadID: String) throws` — replaces label set (used by archive: removing `"INBOX"`).

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/MailStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

@Suite struct MailStoreTests {
    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    private func thread(_ id: String, date: TimeInterval, labels: [String]) -> MailThread {
        MailThread(id: id, snippet: id, lastMessageDate: Date(timeIntervalSince1970: date),
                   isUnread: false, hasAttachments: false, labelIDs: labels)
    }

    @Test func inboxThreadsAreFilteredAndSortedNewestFirst() throws {
        let store = try makeStore()
        try store.upsert(thread("old", date: 100, labels: ["INBOX"]))
        try store.upsert(thread("new", date: 200, labels: ["INBOX"]))
        try store.upsert(thread("archived", date: 300, labels: ["Label_1"]))

        let inbox = try store.inboxThreads()
        #expect(inbox.map(\.id) == ["new", "old"])
    }

    @Test func upsertReplacesExistingThread() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 100, labels: ["INBOX"]))
        try store.upsert(thread("t", date: 100, labels: ["INBOX"])) // snippet "t" again
        let count = try store.inboxThreads().count
        #expect(count == 1)
    }

    @Test func messagesInThreadSortedOldestFirst() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 0, labels: ["INBOX"]))
        try store.upsert(Message(id: "m2", threadID: "t", sender: "x", recipients: [],
                                 subject: "", date: Date(timeIntervalSince1970: 20),
                                 bodyHTML: nil, bodyText: nil, isUnread: false))
        try store.upsert(Message(id: "m1", threadID: "t", sender: "x", recipients: [],
                                 subject: "", date: Date(timeIntervalSince1970: 10),
                                 bodyHTML: nil, bodyText: nil, isUnread: false))
        let ids = try store.messages(inThread: "t").map(\.id)
        #expect(ids == ["m1", "m2"])
    }

    @Test func setLabelsArchivesThreadOutOfInbox() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 100, labels: ["INBOX"]))
        try store.setLabels([], onThread: "t")
        let isEmpty = try store.inboxThreads().isEmpty
        #expect(isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MailStoreTests`
Expected: FAIL — `MailStore` not found.

- [ ] **Step 3: Implement `MailStore`**

`Sources/VeloCore/Storage/MailStore.swift`:
```swift
import Foundation
import GRDB

public final class MailStore {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func upsert(_ thread: MailThread) throws {
        try database.dbQueue.write { try thread.save($0) }
    }

    public func upsert(_ message: Message) throws {
        try database.dbQueue.write { try message.save($0) }
    }

    public func inboxThreads() throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
    }

    public func messages(inThread threadID: String) throws -> [Message] {
        try database.dbQueue.read { db in
            try Message
                .filter(Column("threadID") == threadID)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    public func setLabels(_ labelIDs: [String], onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.labelIDs = labelIDs
            try thread.update(db)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MailStoreTests`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Storage/MailStore.swift Tests/VeloCoreTests/MailStoreTests.swift
git commit -m "feat: add MailStore read/write API"
```

---

### Task 5: Reactive inbox observation

**Files:**
- Modify: `Sources/VeloCore/Storage/MailStore.swift` (add observation method)
- Test: `Tests/VeloCoreTests/MailStoreObservationTests.swift`

**Interfaces:**
- Consumes: `MailStore`, GRDB `ValueObservation`.
- Produces:
  - `func observeInboxThreads(onChange: @escaping ([MailThread]) -> Void) -> AnyDatabaseCancellable`
    — emits the current inbox immediately, then again on every relevant DB change. Caller retains the returned cancellable to keep the observation alive.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/MailStoreObservationTests.swift`:
```swift
import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct MailStoreObservationTests {
    /// Thread-safe collector for emissions delivered from GRDB's scheduler.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [[String]] = []
        func append(_ value: [String]) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [[String]] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// Polls `condition` up to ~2s (100 × 20ms), failing the test if never true.
    private func pollUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("condition not met within timeout")
    }

    @Test func observationEmitsInitialThenUpdatesOnInsert() async throws {
        let store = MailStore(try AppDatabase.makeInMemory())
        let collector = Collector()

        let cancellable = store.observeInboxThreads { collector.append($0.map(\.id)) }
        defer { cancellable.cancel() }

        // `.immediate` scheduling delivers the initial value synchronously.
        await pollUntil { !collector.values.isEmpty }
        #expect(collector.values.first == [])

        try store.upsert(MailThread(id: "t", snippet: "",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))

        // The post-write emission is delivered asynchronously on the main queue.
        await pollUntil { collector.values.count >= 2 }
        #expect(collector.values.last == ["t"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MailStoreObservationTests`
Expected: FAIL — `observeInboxThreads` not found.

- [ ] **Step 3: Add the observation method to `MailStore`**

Append inside the `MailStore` class in `Sources/VeloCore/Storage/MailStore.swift`:
```swift
    public func observeInboxThreads(
        onChange: @escaping ([MailThread]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try MailThread
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
        return observation.start(
            in: database.dbQueue,
            scheduling: .immediate,
            onError: { _ in },
            onChange: onChange
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MailStoreObservationTests`
Expected: PASS. (With `.immediate` scheduling, the first emission is synchronous on the calling thread.)

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: ALL tests across all files PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VeloCore/Storage/MailStore.swift Tests/VeloCoreTests/MailStoreObservationTests.swift
git commit -m "feat: add reactive inbox observation to MailStore"
```

---

## What this plan delivers

A tested `VeloCore` package with: a migrated SQLite database, `MailThread`/`Message` models, a `MailStore` read/write API (inbox filtering, thread messages, archive via label edit), and reactive inbox observation. All runnable today with `swift test` — no Xcode required.

## Next plans (not in this one)

- **VeloCore: Auth** — OAuth 2.0 with Gmail scopes, Keychain token storage. *Prerequisite:* you create a Google Cloud project + OAuth client (manual; I'll write step-by-step instructions).
- **VeloCore: GmailSync** — backfill + incremental `history.list` + outbound mutation queue, reconciling into `MailStore`.
- **VeloApp (GUI)** — SwiftUI shell + AppKit message list + KeyboardEngine. *Prerequisite:* install Xcode from the App Store.

## Self-Review

- **Spec coverage:** This plan implements the spec's Storage module (§4 "Storage", §5 Data Model for thread/message, §6 "UI reads only from local" via reactive observation). Auth, GmailSync, KeyboardEngine, UI are explicitly deferred to named follow-up plans. `sync_state` and `pending_mutation` tables (§5) are deferred to the GmailSync plan where they are first used (YAGNI — nothing reads them yet).
- **Placeholder scan:** No TBD/TODO; every code step shows complete code.
- **Type consistency:** `MailThread`/`Message` field names and `MailStore` method signatures match across Tasks 3–5. `labelIDs` JSON `LIKE '%"INBOX"%'` filter is used identically in `inboxThreads()` and `observeInboxThreads()`.
