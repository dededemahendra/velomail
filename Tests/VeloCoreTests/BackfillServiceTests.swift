import Testing
import Foundation
import GRDB
@testable import VeloCore

private func makeDTO(id: String, thread: String, labels: [String],
                     internalDate: String, snippet: String) -> GmailMessageDTO {
    let labelsJSON = labels.map { "\"\($0)\"" }.joined(separator: ",")
    let json = """
    {"id":"\(id)","threadId":"\(thread)","labelIds":[\(labelsJSON)],"snippet":"\(snippet)",
     "internalDate":"\(internalDate)",
     "payload":{"mimeType":"text/plain",
       "headers":[{"name":"From","value":"a@b.com"},{"name":"Subject","value":"s"}],
       "body":{"data":"cGxhaW4gYm9keQ"}}}
    """
    return try! JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
}

/// Scripted Gmail source. Paging restarts whenever a fresh backfill begins
/// (`pageToken == nil`), so the same instance can drive repeated backfills.
private final class ScriptedSource: GmailReading, @unchecked Sendable {
    let pages: [(ids: [String], next: String?)]
    let messages: [String: GmailMessageDTO]
    let profileHistoryId: String
    private(set) var getCallCount = 0
    private(set) var callLog: [String] = []
    private var pageIndex = 0

    init(pages: [(ids: [String], next: String?)], messages: [GmailMessageDTO],
         profileHistoryId: String = "5000") {
        self.pages = pages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        self.profileHistoryId = profileHistoryId
    }

    func getProfile() async throws -> GmailProfile {
        callLog.append("profile")
        return GmailProfile(emailAddress: "u@x.com", historyId: profileHistoryId)
    }

    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        callLog.append("list")
        if pageToken == nil { pageIndex = 0 }
        let page = pages[pageIndex]
        pageIndex += 1
        return (page.ids, page.next)
    }

    func getMessage(id: String) async throws -> GmailMessageDTO {
        callLog.append("get")
        getCallCount += 1
        return messages[id]!
    }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError("fetchHistory not used by backfill")
    }
}

/// Records peak concurrency and can fail a chosen message, so "stores as it
/// goes" and "fetches in parallel" are observable rather than assumed.
private final class ObservingSource: GmailReading, @unchecked Sendable {
    let ids: [String]
    var failOn: String?
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var peakConcurrency = 0
    private(set) var fetched: [String] = []
    /// Called after each fetch, so a test can look at the store mid-backfill.
    var onFetch: (@Sendable (Int) -> Void)?

    init(ids: [String], failOn: String? = nil) {
        self.ids = ids
        self.failOn = failOn
    }

    func getProfile() async throws -> GmailProfile {
        GmailProfile(emailAddress: "u@x.com", historyId: "5000")
    }

    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        (ids, nil)
    }

    func getMessage(id: String) async throws -> GmailMessageDTO {
        lock.lock(); inFlight += 1; peakConcurrency = max(peakConcurrency, inFlight); lock.unlock()
        defer { lock.lock(); inFlight -= 1; lock.unlock() }

        await Task.yield()
        if id == failOn { throw AuthError.invalidResponse }

        lock.lock(); fetched.append(id); let count = fetched.count; lock.unlock()
        onFetch?(count)
        return makeDTO(id: id, thread: "t-\(id)", labels: ["INBOX"],
                       internalDate: "1000", snippet: "s")
    }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError("not used by backfill")
    }
}

@Suite struct BackfillServiceTests {
    private let account = "acct-1"

    private func makeContext(_ source: GmailReading) throws
        -> (BackfillService, MailStore, SyncStateStore) {
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let syncStore = SyncStateStore(db)
        let service = BackfillService(source: source, store: mailStore, syncState: syncStore)
        return (service, mailStore, syncStore)
    }

    @Test func reconcilesPagedMessagesIntoInbox() async throws {
        let source = ScriptedSource(
            pages: [(["m1", "m2"], "p2"), (["m3"], nil)],
            messages: [
                makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "older t1"),
                makeDTO(id: "m2", thread: "t1", labels: ["INBOX", "UNREAD"], internalDate: "2000", snippet: "newer t1"),
                makeDTO(id: "m3", thread: "t2", labels: ["INBOX"], internalDate: "1500", snippet: "only t2"),
            ])
        let (service, store, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 10)

        let threads = try store.inboxThreads()
        #expect(Set(threads.map(\.id)) == ["t1", "t2"])
        #expect(try store.messages(inThread: "t1").count == 2)
        #expect(try store.messages(inThread: "t2").count == 1)

        let t1 = try #require(threads.first { $0.id == "t1" })
        #expect(t1.snippet == "newer t1")
        #expect(t1.isUnread == true)
        #expect(t1.lastMessageDate == Date(timeIntervalSince1970: 2))
    }

    @Test func isIdempotentOnSecondRun() async throws {
        let source = ScriptedSource(
            pages: [(["m1", "m2"], nil)],
            messages: [
                makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a"),
                makeDTO(id: "m2", thread: "t2", labels: ["INBOX"], internalDate: "2000", snippet: "b"),
            ])
        let (service, store, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 10)
        try await service.backfillInbox(accountID: account, maxMessages: 10)

        #expect(try store.inboxThreads().count == 2)
        #expect(try store.messages(inThread: "t1").count == 1)
        #expect(try store.messages(inThread: "t2").count == 1)
    }

    @Test func respectsMaxMessagesCap() async throws {
        let source = ScriptedSource(
            pages: [(["m1", "m2", "m3"], "p2")],
            messages: [
                makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a"),
                makeDTO(id: "m2", thread: "t2", labels: ["INBOX"], internalDate: "2000", snippet: "b"),
                makeDTO(id: "m3", thread: "t3", labels: ["INBOX"], internalDate: "3000", snippet: "c"),
            ])
        let (service, store, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 2)

        #expect(source.getCallCount == 2)
        #expect(try store.inboxThreads().count == 2)
    }

    @Test func recordsHistoryIdBaselineAndBackfillComplete() async throws {
        let source = ScriptedSource(
            pages: [(["m1"], nil)],
            messages: [makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a")],
            profileHistoryId: "7777")
        let (service, _, syncStore) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 10)

        let state = try syncStore.load(accountID: account)
        #expect(state?.historyId == "7777")          // baseline from getProfile, not internalDate
        #expect(state?.backfillComplete == true)
    }

    @Test func capturesBaselineBeforeListing() async throws {
        let source = ScriptedSource(
            pages: [(["m1"], nil)],
            messages: [makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a")])
        let (service, _, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 10)

        let log = source.callLog
        #expect(log.first == "profile")
        #expect(log.firstIndex(of: "profile")! < log.firstIndex(of: "list")!)
    }

    @Test func reRunOverwritesBaselineAndKeepsComplete() async throws {
        let source = ScriptedSource(
            pages: [(["m1"], nil)],
            messages: [makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a")],
            profileHistoryId: "9000")
        let (service, _, syncStore) = try makeContext(source)
        try syncStore.save(SyncState(accountID: account, historyId: "1", backfillComplete: true))

        try await service.backfillInbox(accountID: account, maxMessages: 10)

        let state = try syncStore.load(accountID: account)
        #expect(state?.historyId == "9000")
        #expect(state?.backfillComplete == true)
    }

    @Test func backfillPersistsTheProfileEmailAddress() async throws {
        let source = ScriptedSource(
            pages: [(["m1"], nil)],
            messages: [makeDTO(id: "m1", thread: "t1", labels: ["INBOX"],
                               internalDate: "1000", snippet: "s")])
        let (service, _, syncStore) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 10)

        // The address is already on the wire; discarding it is what left the
        // app sending as "me@example.com".
        #expect(try syncStore.load(accountID: account)?.emailAddress == "u@x.com")
    }

    @Test func backfillKeepsTheEmailAddressOnASecondRun() async throws {
        let source = ScriptedSource(
            pages: [(["m1"], nil)],
            messages: [makeDTO(id: "m1", thread: "t1", labels: ["INBOX"],
                               internalDate: "1000", snippet: "s")])
        let (service, _, syncStore) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 10)
        try await service.backfillInbox(accountID: account, maxMessages: 10)

        #expect(try syncStore.load(accountID: account)?.emailAddress == "u@x.com")
    }

    // MARK: - Progressive, parallel backfill

    @Test func messagesAreFetchedConcurrently() async throws {
        let source = ObservingSource(ids: (0..<60).map { "m\($0)" })
        let (service, _, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 60)

        // Sequential fetching is what made a real first sync take minutes.
        #expect(source.peakConcurrency > 1)
    }

    @Test func concurrencyIsBoundedRatherThanUnleashingEveryRequestAtOnce() async throws {
        let source = ObservingSource(ids: (0..<200).map { "m\($0)" })
        let (service, _, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 200)

        // 200 simultaneous requests would be rate-limited and would blow the
        // connection pool.
        #expect(source.peakConcurrency <= BackfillService.maximumConcurrentFetches)
    }

    @Test func everyMessageStillArrives() async throws {
        let source = ObservingSource(ids: (0..<60).map { "m\($0)" })
        let (service, store, _) = try makeContext(source)

        try await service.backfillInbox(accountID: account, maxMessages: 60)

        #expect(try store.inboxThreads().count == 60)
    }

    @Test func theInboxFillsBeforeTheBackfillFinishes() async throws {
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let source = ObservingSource(ids: (0..<80).map { "m\($0)" })
        let seenMidway = LockedBox()
        source.onFetch = { count in
            if count == 70, let rows = try? mailStore.inboxThreads().count { seenMidway.set(rows) }
        }
        let service = BackfillService(source: source, store: mailStore,
                                      syncState: SyncStateStore(db))

        try await service.backfillInbox(accountID: account, maxMessages: 80)

        // The v1 design asked for exactly this: "store as we go so the inbox
        // populates progressively". Waiting for all 500 is what showed an empty
        // inbox for minutes on a real account.
        #expect(seenMidway.value > 0)
    }

    @Test func aFailureMidwayKeepsWhatWasAlreadyStored() async throws {
        let source = ObservingSource(ids: (0..<80).map { "m\($0)" }, failOn: "m75")
        let (service, store, syncStore) = try makeContext(source)

        await #expect(throws: (any Error).self) {
            try await service.backfillInbox(accountID: account, maxMessages: 80)
        }

        // Losing 74 good messages because the 75th failed is the difference
        // between a slow first sync and one that never completes.
        #expect(try store.inboxThreads().count > 0)
        // The cursor is not recorded, so the next pass resumes rather than
        // believing it finished.
        #expect(try syncStore.load(accountID: account)?.backfillComplete != true)
    }
}

/// Thread-safe int for observing storage from inside a concurrent fetch.
private final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func set(_ value: Int) { lock.lock(); stored = value; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
