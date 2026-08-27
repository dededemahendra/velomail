import Testing
import Foundation
@testable import VeloCore

/// Serves pages per label so paging past the cap can be observed.
private final class PagingSource: GmailReading, @unchecked Sendable {
    /// label -> pages of (ids, nextPageToken)
    private let pages: [String: [([String], String?)]]
    private(set) var requestedTokens: [String?] = []
    private(set) var fetched: [String] = []

    init(pages: [String: [([String], String?)]]) { self.pages = pages }

    func getProfile() async throws -> GmailProfile {
        GmailProfile(emailAddress: "me@x.com", historyId: "1")
    }

    func listMessageIDs(labelID: String, pageToken: String?)
        async throws -> (ids: [String], nextPageToken: String?) {
        guard let forLabel = pages[labelID] else { return ([], nil) }
        requestedTokens.append(pageToken)
        let index = pageToken.flatMap { Int($0) } ?? 0
        guard index < forLabel.count else { return ([], nil) }
        return forLabel[index]
    }

    func getMessage(id: String) async throws -> GmailMessageDTO {
        fetched.append(id)
        let json = """
        {"id":"\(id)","threadId":"t-\(id)","labelIds":["INBOX"],"snippet":"s",
         "internalDate":"1000",
         "payload":{"mimeType":"text/plain",
           "headers":[{"name":"From","value":"a@b.com"},{"name":"Subject","value":"s"}],
           "body":{"data":"cGxhaW4gYm9keQ"}}}
        """
        return try JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
    }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError("history not used here")
    }
}

@Suite struct LoadOlderTests {
    private let account = "primary"

    private func makeContext(_ source: PagingSource)
        throws -> (BackfillService, MailStore, SyncStateStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let syncStore = SyncStateStore(db)
        return (BackfillService(source: source, store: store, syncState: syncStore),
                store, syncStore)
    }

    // MARK: - Where the first pass stopped

    @Test func theCapLeavesACursorToCarryOnFrom() throws {
        // Without it "load older" would start again from the newest message and
        // fetch the same five hundred.
        let source = PagingSource(pages: ["INBOX": [(["a"], "1"), (["b"], nil)]])
        let (service, _, syncStore) = try makeContext(source)

        let waiter = Task { try await service.backfillInbox(accountID: account, maxMessages: 1) }
        _ = try awaitValue(waiter)

        #expect(try syncStore.load(accountID: account)?.olderCursor(for: "INBOX") == "1")
    }

    @Test func aLabelFullyFetchedLeavesNoCursor() throws {
        // Nothing older to ask for, so the command should know to say so.
        let source = PagingSource(pages: ["INBOX": [(["a"], nil)]])
        let (service, _, syncStore) = try makeContext(source)

        let waiter = Task { try await service.backfillInbox(accountID: account, maxMessages: 50) }
        _ = try awaitValue(waiter)

        #expect(try syncStore.load(accountID: account)?.olderCursor(for: "INBOX") == nil)
    }

    // MARK: - Fetching more

    @Test func loadingOlderContinuesFromTheCursor() throws {
        let source = PagingSource(pages: ["INBOX": [(["a"], "1"), (["b"], nil)]])
        let (service, store, _) = try makeContext(source)
        _ = try awaitValue(Task { try await service.backfillInbox(accountID: account, maxMessages: 1) })

        _ = try awaitValue(Task { try await service.loadOlder(accountID: account, maxMessages: 1) })

        #expect(source.fetched == ["a", "b"])          // never the same message twice
        #expect(try store.inboxThreads().count == 2)
    }

    @Test func loadingOlderWithNothingLeftIsHarmless() throws {
        let source = PagingSource(pages: ["INBOX": [(["a"], nil)]])
        let (service, _, _) = try makeContext(source)
        _ = try awaitValue(Task { try await service.backfillInbox(accountID: account, maxMessages: 50) })

        let more = try awaitValue(Task { try await service.loadOlder(accountID: account, maxMessages: 50) })

        #expect(more == 0)
        #expect(source.fetched == ["a"])
    }

    @Test func loadingOlderReportsHowMuchItFound() throws {
        // The caller says "12 older messages" rather than guessing.
        let source = PagingSource(pages: ["INBOX": [(["a"], "1"), (["b", "c"], nil)]])
        let (service, _, _) = try makeContext(source)
        _ = try awaitValue(Task { try await service.backfillInbox(accountID: account, maxMessages: 1) })

        let more = try awaitValue(Task { try await service.loadOlder(accountID: account, maxMessages: 50) })

        #expect(more == 2)
    }

    @Test func loadingOlderDoesNotDisturbTheHistoryCursor() throws {
        // Older mail says nothing about what has happened since.
        let source = PagingSource(pages: ["INBOX": [(["a"], "1"), (["b"], nil)]])
        let (service, _, syncStore) = try makeContext(source)
        _ = try awaitValue(Task { try await service.backfillInbox(accountID: account, maxMessages: 1) })
        let before = try syncStore.load(accountID: account)?.historyId

        _ = try awaitValue(Task { try await service.loadOlder(accountID: account, maxMessages: 1) })

        #expect(try syncStore.load(accountID: account)?.historyId == before)
    }
}

/// Runs an async task to completion from a synchronous test.
private func awaitValue<T>(_ task: Task<T, Error>) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var outcome: Result<T, Error>!
    Task {
        outcome = await task.result
        semaphore.signal()
    }
    semaphore.wait()
    return try outcome.get()
}
