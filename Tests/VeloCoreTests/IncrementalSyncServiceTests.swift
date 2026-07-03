import Testing
import Foundation
import GRDB
@testable import VeloCore

private func makeDTO(id: String, thread: String, labels: [String] = ["INBOX"],
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

private func historyPage(added: [(id: String, thread: String)],
                         historyId: String, nextPageToken: String?) -> GmailHistoryResponse {
    let addedJSON = added
        .map { "{\"message\":{\"id\":\"\($0.id)\",\"threadId\":\"\($0.thread)\"}}" }
        .joined(separator: ",")
    let nextJSON = nextPageToken.map { ",\"nextPageToken\":\"\($0)\"" } ?? ""
    let json = "{\"history\":[{\"id\":\"1\",\"messagesAdded\":[\(addedJSON)]}],\"historyId\":\"\(historyId)\"\(nextJSON)}"
    return try! JSONDecoder().decode(GmailHistoryResponse.self, from: Data(json.utf8))
}

/// Scripted history source. Paging restarts on a fresh sync (`pageToken == nil`).
private final class HistorySource: GmailReading {
    let pages: [GmailHistoryResponse]
    let messages: [String: GmailMessageDTO]
    private var index = 0
    private(set) var getCallCount = 0
    private(set) var lastStartHistoryId: String?

    init(pages: [GmailHistoryResponse], messages: [GmailMessageDTO]) {
        self.pages = pages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        lastStartHistoryId = startHistoryId
        if pageToken == nil { index = 0 }
        let page = pages[index]
        index += 1
        return page
    }

    func getMessage(id: String) async throws -> GmailMessageDTO {
        getCallCount += 1
        return messages[id]!
    }

    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        fatalError("list not used by incremental sync")
    }

    func getProfile() async throws -> GmailProfile {
        fatalError("getProfile not used by incremental sync")
    }
}

@Suite struct IncrementalSyncServiceTests {
    private let account = "acct-1"

    private func makeContext(pages: [GmailHistoryResponse], messages: [GmailMessageDTO],
                             seedHistoryId: String?) throws
        -> (IncrementalSyncService, MailStore, SyncStateStore, HistorySource) {
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let syncStore = SyncStateStore(db)
        if let seedHistoryId {
            try syncStore.save(SyncState(accountID: account, historyId: seedHistoryId, backfillComplete: true))
        }
        let source = HistorySource(pages: pages, messages: messages)
        let service = IncrementalSyncService(source: source, store: mailStore, syncState: syncStore)
        return (service, mailStore, syncStore, source)
    }

    @Test func appliesAddedMessagesAndAdvancesCursor() async throws {
        let (service, mailStore, syncStore, source) = try makeContext(
            pages: [historyPage(added: [("m1", "t1")], historyId: "1050", nextPageToken: nil)],
            messages: [makeDTO(id: "m1", thread: "t1", internalDate: "1000", snippet: "new")],
            seedHistoryId: "1000")

        try await service.sync(accountID: account)

        #expect(try mailStore.inboxThreads().map(\.id) == ["t1"])
        #expect(try mailStore.messages(inThread: "t1").count == 1)
        #expect(try syncStore.load(accountID: account)?.historyId == "1050")
        #expect(source.lastStartHistoryId == "1000")
    }

    @Test func pagesThroughHistory() async throws {
        let (service, mailStore, syncStore, _) = try makeContext(
            pages: [
                historyPage(added: [("m1", "t1")], historyId: "1050", nextPageToken: "hp2"),
                historyPage(added: [("m2", "t2")], historyId: "1100", nextPageToken: nil),
            ],
            messages: [
                makeDTO(id: "m1", thread: "t1", internalDate: "1000", snippet: "a"),
                makeDTO(id: "m2", thread: "t2", internalDate: "2000", snippet: "b"),
            ],
            seedHistoryId: "1000")

        try await service.sync(accountID: account)

        #expect(try Set(mailStore.inboxThreads().map(\.id)) == ["t1", "t2"])
        #expect(try syncStore.load(accountID: account)?.historyId == "1100")
    }

    @Test func isIdempotentOnSecondRun() async throws {
        let (service, mailStore, _, _) = try makeContext(
            pages: [historyPage(added: [("m1", "t1")], historyId: "1050", nextPageToken: nil)],
            messages: [makeDTO(id: "m1", thread: "t1", internalDate: "1000", snippet: "new")],
            seedHistoryId: "1000")

        try await service.sync(accountID: account)
        try await service.sync(accountID: account)

        #expect(try mailStore.inboxThreads().count == 1)
        #expect(try mailStore.messages(inThread: "t1").count == 1)
    }

    @Test func throwsNotInitializedWhenNoCursor() async throws {
        let (service, _, _, source) = try makeContext(
            pages: [historyPage(added: [], historyId: "1", nextPageToken: nil)],
            messages: [],
            seedHistoryId: nil)

        await #expect(throws: SyncError.notInitialized) {
            try await service.sync(accountID: account)
        }
        #expect(source.getCallCount == 0)
    }
}
