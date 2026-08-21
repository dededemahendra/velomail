import Testing
import Foundation
import GRDB
@testable import VeloCore

private func makeDTO(id: String, thread: String) -> GmailMessageDTO {
    let json = """
    {"id":"\(id)","threadId":"\(thread)","labelIds":["INBOX"],"snippet":"s","internalDate":"1000",
     "payload":{"mimeType":"text/plain","headers":[{"name":"Subject","value":"s"}]}}
    """
    return try! JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
}

private func historyPage(added: [(id: String, thread: String)], historyId: String, next: String?) -> GmailHistoryResponse {
    let addedJSON = added.map { "{\"message\":{\"id\":\"\($0.id)\",\"threadId\":\"\($0.thread)\"}}" }
        .joined(separator: ",")
    let nextJSON = next.map { ",\"nextPageToken\":\"\($0)\"" } ?? ""
    let json = "{\"history\":[{\"id\":\"1\",\"messagesAdded\":[\(addedJSON)]}],\"historyId\":\"\(historyId)\"\(nextJSON)}"
    return try! JSONDecoder().decode(GmailHistoryResponse.self, from: Data(json.utf8))
}

/// One fake driving backfill (profile/list/get), incremental (fetchHistory/get),
/// and outbound (modify). `Task.yield()` in the read methods guarantees an actor
/// suspension so the reentrancy-coalescing test is deterministic.
private final class FakeGmail: GmailReading, GmailWriting, @unchecked Sendable {
    let profileHistoryId: String
    let backfillPages: [(ids: [String], next: String?)]
    let messages: [String: GmailMessageDTO]
    let historyPages: [GmailHistoryResponse]
    var failGetMessage: Bool
    private(set) var callLog: [String] = []
    private(set) var listCallCount = 0
    /// Number of upcoming fetchHistory calls that should 404, which
    /// IncrementalSyncService maps to SyncError.historyExpired.
    var historyExpiredCalls = 0
    private var backfillIndex = 0
    private var historyIndex = 0

    init(profileHistoryId: String, backfillPages: [(ids: [String], next: String?)],
         messages: [GmailMessageDTO], historyPages: [GmailHistoryResponse], failGetMessage: Bool = false) {
        self.profileHistoryId = profileHistoryId
        self.backfillPages = backfillPages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        self.historyPages = historyPages
        self.failGetMessage = failGetMessage
    }

    func getProfile() async throws -> GmailProfile {
        await Task.yield()
        callLog.append("profile")
        return GmailProfile(emailAddress: "u@x.com", historyId: profileHistoryId)
    }
    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        callLog.append("list")
        listCallCount += 1
        if pageToken == nil { backfillIndex = 0 }
        let page = backfillPages[backfillIndex]
        backfillIndex += 1
        return (page.ids, page.next)
    }
    func getMessage(id: String) async throws -> GmailMessageDTO {
        callLog.append("get")
        if failGetMessage { throw AuthError.server(code: "500", description: "boom") }
        return messages[id]!
    }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        await Task.yield()
        callLog.append("fetchHistory")
        if historyExpiredCalls > 0 {
            historyExpiredCalls -= 1
            throw AuthError.server(code: "404", description: "history too old")
        }
        if pageToken == nil { historyIndex = 0 }
        let page = historyPages[historyIndex]
        historyIndex += 1
        return page
    }
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        callLog.append("modify")
    }

    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        callLog.append("send")
        return try JSONDecoder().decode(GmailMessageDTO.self, from: Data(
            #"{"id":"sent1","threadId":"t1","labelIds":["SENT"],"internalDate":"100000"}"#.utf8))
    }
}

/// Deterministic clock: records every requested delay (which is how backoff is
/// asserted) and ends the loop by throwing once `stopAfter` sleeps have run.
private final class FakeClock: SyncClock, @unchecked Sendable {
    private(set) var sleeps: [TimeInterval] = []
    private let stopAfter: Int

    init(stopAfter: Int) { self.stopAfter = stopAfter }

    func now() -> Date { Date(timeIntervalSince1970: 0) }

    func sleep(for duration: TimeInterval) async throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        if sleeps.count >= stopAfter { throw CancellationError() }
        await Task.yield()
    }
}

@Suite struct GmailSyncTests {
    private let account = "acct"

    private func makeSync(source: FakeGmail, seedState: SyncState? = nil,
                          seedMutationMessageIDs: [String]? = nil, backfillLimit: Int = 500,
                          clock: SyncClock = SystemSyncClock(), failSeededMutation: Bool = false)
        throws -> (GmailSync, MailStore, SyncStateStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let syncStore = SyncStateStore(db)
        let mutations = MutationStore(db)
        if let seedState { try syncStore.save(seedState) }
        if let ids = seedMutationMessageIDs {
            let payload = OutboundMutationPayload(
                threadID: "seed", messageIDs: ids, addLabelIDs: [], removeLabelIDs: ["INBOX"],
                previousMessageLabels: Dictionary(uniqueKeysWithValues: ids.map { ($0, ["INBOX"]) }))
            let saved = try mutations.enqueue(PendingMutation(kind: .archive, payload: try JSONEncoder().encode(payload),
                                                              createdAt: Date(timeIntervalSince1970: 0)))
            if failSeededMutation, let id = saved.id { try mutations.markFailed(id: id) }
        }
        let backfill = BackfillService(source: source, store: mailStore, syncState: syncStore)
        let incremental = IncrementalSyncService(source: source, store: mailStore, syncState: syncStore)
        let outbound = OutboundService(writer: source, store: mailStore, mutations: mutations, identity: "me@example.com",
                                       now: { Date(timeIntervalSince1970: 0) })
        let sync = GmailSync(accountID: account, backfill: backfill, incremental: incremental,
                             outbound: outbound, syncState: syncStore, backfillLimit: backfillLimit,
                             now: { Date(timeIntervalSince1970: 0) }, clock: clock)
        return (sync, mailStore, syncStore, mutations)
    }

    private func fresh(failGetMessage: Bool = false) -> FakeGmail {
        FakeGmail(profileHistoryId: "5000",
                  backfillPages: [(["mb1"], nil)],
                  messages: [makeDTO(id: "mb1", thread: "tb"), makeDTO(id: "mh1", thread: "th")],
                  historyPages: [historyPage(added: [("mh1", "th")], historyId: "5100", next: nil)],
                  failGetMessage: failGetMessage)
    }

    @Test func freshAccountBackfillsThenIncrementsThenDrains() async throws {
        let source = fresh()
        let (sync, mailStore, syncStore, mutations) = try makeSync(source: source, seedMutationMessageIDs: ["mb1"])

        try await sync.syncNow()

        #expect(try Set(mailStore.inboxThreads().map(\.id)) == ["tb", "th"])
        let state = try syncStore.load(accountID: account)
        #expect(state?.backfillComplete == true)
        #expect(state?.historyId == "5100")
        #expect(try mutations.all().isEmpty)   // seeded mutation drained
    }

    @Test func alreadyBackfilledSkipsBackfill() async throws {
        let source = fresh()
        let (sync, _, syncStore, _) = try makeSync(
            source: source, seedState: SyncState(accountID: account, historyId: "1000", backfillComplete: true))

        try await sync.syncNow()

        #expect(source.listCallCount == 0)   // backfill skipped
        #expect(try syncStore.load(accountID: account)?.historyId == "5100")   // incremental advanced cursor
    }

    @Test func orchestrationOrderIsBackfillThenIncrementalThenDrain() async throws {
        let source = fresh()
        let (sync, _, _, _) = try makeSync(source: source, seedMutationMessageIDs: ["mb1"])

        try await sync.syncNow()

        let log = source.callLog
        let lastList = try #require(log.lastIndex(of: "list"))
        let firstFetch = try #require(log.firstIndex(of: "fetchHistory"))
        let firstModify = try #require(log.firstIndex(of: "modify"))
        #expect(lastList < firstFetch)
        #expect(firstFetch < firstModify)
    }

    @Test func overlappingSyncNowCoalesces() async throws {
        let source = fresh()
        let (sync, _, _, _) = try makeSync(source: source)

        async let a: Void = sync.syncNow()
        async let b: Void = sync.syncNow()
        _ = try await (a, b)

        #expect(source.listCallCount == 1)   // second call coalesced
    }

    @Test func startPerformsOneSyncPass() async throws {
        let source = fresh()
        let (sync, mailStore, _, _) = try makeSync(source: source)

        try await sync.start()

        #expect(try Set(mailStore.inboxThreads().map(\.id)) == ["tb", "th"])
    }

    @Test func errorPropagatesAndClearsSyncingFlag() async throws {
        let source = fresh(failGetMessage: true)
        let (sync, _, _, _) = try makeSync(source: source)

        await #expect(throws: AuthError.self) { try await sync.syncNow() }
        // If isSyncing were stuck true, this second call would return without throwing.
        await #expect(throws: AuthError.self) { try await sync.syncNow() }
    }

    // MARK: - Auto re-backfill (F3)

    @Test func historyExpiredResetsTheCursorAndReBackfillsInTheSamePass() async throws {
        let source = fresh()
        source.historyExpiredCalls = 1
        let (sync, mailStore, syncStore, _) = try makeSync(
            source: source, seedState: SyncState(accountID: account, historyId: "stale", backfillComplete: true))

        try await sync.syncNow()

        // Recovered without the caller doing anything.
        #expect(source.listCallCount == 1)                       // re-backfill ran
        let state = try syncStore.load(accountID: account)
        #expect(state?.backfillComplete == true)
        #expect(state?.historyId == "5100")                      // fresh cursor from history
        #expect(try Set(mailStore.inboxThreads().map(\.id)) == ["tb", "th"])
    }

    @Test func reBackfillIsAttemptedOnlyOncePerPass() async throws {
        let source = fresh()
        source.historyExpiredCalls = 99                          // never recovers
        let (sync, _, _, _) = try makeSync(
            source: source, seedState: SyncState(accountID: account, historyId: "stale", backfillComplete: true))

        await #expect(throws: SyncError.historyExpired) {
            try await sync.syncNow()
        }
        #expect(source.listCallCount == 1)                       // one attempt, not a spin
    }

    @Test func notInitializedAlsoTriggersABackfill() async throws {
        let source = fresh()
        // Flagged complete but with no cursor: incremental cannot start.
        let (sync, _, syncStore, _) = try makeSync(
            source: source, seedState: SyncState(accountID: account, historyId: nil, backfillComplete: true))

        try await sync.syncNow()

        #expect(source.listCallCount == 1)
        #expect(try syncStore.load(accountID: account)?.historyId == "5100")
    }

    @Test func aNormalPassDoesNotReBackfill() async throws {
        let source = fresh()
        let (sync, _, _, _) = try makeSync(
            source: source, seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true))

        try await sync.syncNow()

        #expect(source.listCallCount == 0)                       // nothing to re-establish
    }

    // MARK: - Status (F4)

    @Test func statusStartsIdle() async throws {
        let (sync, _, _, _) = try makeSync(source: fresh())
        let status = await sync.status
        #expect(status == .idle)
    }

    @Test func statusIsUpToDateAfterASuccessfulPass() async throws {
        let (sync, _, _, _) = try makeSync(source: fresh())

        try await sync.syncNow()

        let status = await sync.status
        #expect(status == .upToDate(lastSyncedAt: Date(timeIntervalSince1970: 0)))
    }

    @Test func statusIsOfflineAfterATransientFailure() async throws {
        let (sync, _, _, _) = try makeSync(source: fresh(failGetMessage: true))

        await #expect(throws: AuthError.self) { try await sync.syncNow() }

        let status = await sync.status
        #expect(status == .offline(consecutiveFailures: 1))
    }

    @Test func consecutiveFailuresAccumulate() async throws {
        let (sync, _, _, _) = try makeSync(source: fresh(failGetMessage: true))

        await #expect(throws: AuthError.self) { try await sync.syncNow() }
        await #expect(throws: AuthError.self) { try await sync.syncNow() }

        let status = await sync.status
        #expect(status == .offline(consecutiveFailures: 2))
    }

    @Test func aSuccessfulPassClearsTheFailureCount() async throws {
        let source = fresh(failGetMessage: true)
        let (sync, _, _, _) = try makeSync(source: source)
        await #expect(throws: AuthError.self) { try await sync.syncNow() }

        source.failGetMessage = false                    // network came back
        try await sync.syncNow()

        // Recovery must be immediate, not served out behind a stale backoff.
        let status = await sync.status
        #expect(status == .upToDate(lastSyncedAt: Date(timeIntervalSince1970: 0)))
    }

    @Test func transientFailureDoesNotAdvanceTheCursor() async throws {
        let (sync, _, syncStore, _) = try makeSync(
            source: fresh(failGetMessage: true),
            seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true))

        await #expect(throws: AuthError.self) { try await sync.syncNow() }

        // A failed pass must leave the cursor alone so the next one retries it.
        #expect(try syncStore.load(accountID: account)?.historyId == "5000")
    }

    // MARK: - Polling loop (F5)

    @Test func runPollsRepeatedlyAtTheConfiguredInterval() async throws {
        let source = fresh()
        let clock = FakeClock(stopAfter: 3)
        let (sync, _, _, _) = try makeSync(
            source: source,
            seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true),
            clock: clock)

        await sync.run(interval: 60)

        #expect(clock.sleeps == [60, 60, 60])
        #expect(source.callLog.filter { $0 == "fetchHistory" }.count == 3)
    }

    @Test func runSleepsForTheBackoffDelayAfterAFailedPass() async throws {
        let clock = FakeClock(stopAfter: 3)
        let (sync, _, _, _) = try makeSync(
            source: fresh(failGetMessage: true),
            seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true),
            clock: clock)

        await sync.run(interval: 60)

        // Standard policy: 2s doubling. The poll interval is not used while failing.
        #expect(clock.sleeps == [2, 4, 8])
    }

    @Test func runReturnsToTheIntervalOnceAPassSucceeds() async throws {
        let source = fresh(failGetMessage: true)
        let clock = RecoveringClock(recoverAfter: 2, source: source)
        let (sync, _, _, _) = try makeSync(
            source: source,
            seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true),
            clock: clock)

        await sync.run(interval: 60)

        #expect(clock.sleeps == [2, 4, 60])
    }

    @Test func runStopsWhenTheTaskIsCancelled() async throws {
        let clock = FakeClock(stopAfter: 10_000)
        let (sync, _, _, _) = try makeSync(
            source: fresh(),
            seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true),
            clock: clock)

        let task = Task { await sync.run(interval: 60) }
        task.cancel()
        await task.value      // must terminate rather than poll forever

        #expect(clock.sleeps.count < 10_000)
    }

    @Test func aPassRetriesFailedMutations() async throws {
        let (sync, _, _, mutations) = try makeSync(
            source: fresh(),
            seedState: SyncState(accountID: account, historyId: "5000", backfillComplete: true),
            seedMutationMessageIDs: ["mb1"], failSeededMutation: true)
        #expect(try mutations.pending().isEmpty)          // stranded before the pass

        try await sync.syncNow()

        #expect(try mutations.all().isEmpty)              // requeued, then drained
    }

    // MARK: - Non-transient failures

    @Test func statusIsFailedAfterANonTransientError() async throws {
        let source = fresh()
        source.historyExpiredCalls = 99                   // never recovers
        let (sync, _, _, _) = try makeSync(
            source: source,
            seedState: SyncState(accountID: account, historyId: "stale", backfillComplete: true))

        await #expect(throws: SyncError.historyExpired) { try await sync.syncNow() }

        // Must not be left on .syncing, or a UI shows a spinner forever.
        let status = await sync.status
        var isFailed = false
        if case .failed = status { isFailed = true }
        #expect(isFailed)
    }

    @Test func runBacksOffAfterANonTransientFailureToo() async throws {
        let source = fresh()
        source.historyExpiredCalls = 99
        let clock = FakeClock(stopAfter: 3)
        let (sync, _, _, _) = try makeSync(
            source: source,
            seedState: SyncState(accountID: account, historyId: "stale", backfillComplete: true),
            clock: clock)

        await sync.run(interval: 60)

        // A failure that will not fix itself must not be retried at full rate.
        #expect(clock.sleeps == [2, 4, 8])
    }
}

/// Clock that lets the source start succeeding after `recoverAfter` sleeps, so
/// the loop can be observed returning from backoff to the normal interval.
private final class RecoveringClock: SyncClock, @unchecked Sendable {
    private(set) var sleeps: [TimeInterval] = []
    private let recoverAfter: Int
    private let source: FakeGmail

    init(recoverAfter: Int, source: FakeGmail) {
        self.recoverAfter = recoverAfter
        self.source = source
    }

    func now() -> Date { Date(timeIntervalSince1970: 0) }

    func sleep(for duration: TimeInterval) async throws {
        try Task.checkCancellation()
        sleeps.append(duration)
        if sleeps.count == recoverAfter { source.failGetMessage = false }
        if sleeps.count >= recoverAfter + 1 { throw CancellationError() }
        await Task.yield()
    }
}
