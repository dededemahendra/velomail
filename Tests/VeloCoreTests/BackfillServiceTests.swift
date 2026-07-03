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
private final class ScriptedSource: GmailReading {
    let pages: [(ids: [String], next: String?)]
    let messages: [String: GmailMessageDTO]
    private(set) var getCallCount = 0
    private var pageIndex = 0

    init(pages: [(ids: [String], next: String?)], messages: [GmailMessageDTO]) {
        self.pages = pages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        if pageToken == nil { pageIndex = 0 }
        let page = pages[pageIndex]
        pageIndex += 1
        return (page.ids, page.next)
    }

    func getMessage(id: String) async throws -> GmailMessageDTO {
        getCallCount += 1
        return messages[id]!
    }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError("fetchHistory not used by backfill")
    }

    func getProfile() async throws -> GmailProfile {
        GmailProfile(emailAddress: "u@x.com", historyId: "5000")
    }
}

@Suite struct BackfillServiceTests {
    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    @Test func reconcilesPagedMessagesIntoInbox() async throws {
        let messages = [
            makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "older t1"),
            makeDTO(id: "m2", thread: "t1", labels: ["INBOX", "UNREAD"], internalDate: "2000", snippet: "newer t1"),
            makeDTO(id: "m3", thread: "t2", labels: ["INBOX"], internalDate: "1500", snippet: "only t2"),
        ]
        let source = ScriptedSource(
            pages: [(["m1", "m2"], "p2"), (["m3"], nil)],
            messages: messages)
        let store = try makeStore()
        let service = BackfillService(source: source, store: store)

        try await service.backfillInbox(maxMessages: 10)

        let threads = try store.inboxThreads()
        #expect(Set(threads.map(\.id)) == ["t1", "t2"])
        #expect(try store.messages(inThread: "t1").count == 2)
        #expect(try store.messages(inThread: "t2").count == 1)

        let t1 = try #require(threads.first { $0.id == "t1" })
        #expect(t1.snippet == "newer t1")          // newest message in thread
        #expect(t1.isUnread == true)                // any message unread
        #expect(t1.lastMessageDate == Date(timeIntervalSince1970: 2))
    }

    @Test func isIdempotentOnSecondRun() async throws {
        let messages = [
            makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a"),
            makeDTO(id: "m2", thread: "t2", labels: ["INBOX"], internalDate: "2000", snippet: "b"),
        ]
        let source = ScriptedSource(pages: [(["m1", "m2"], nil)], messages: messages)
        let store = try makeStore()
        let service = BackfillService(source: source, store: store)

        try await service.backfillInbox(maxMessages: 10)
        try await service.backfillInbox(maxMessages: 10)

        #expect(try store.inboxThreads().count == 2)
        #expect(try store.messages(inThread: "t1").count == 1)
        #expect(try store.messages(inThread: "t2").count == 1)
    }

    @Test func respectsMaxMessagesCap() async throws {
        let messages = [
            makeDTO(id: "m1", thread: "t1", labels: ["INBOX"], internalDate: "1000", snippet: "a"),
            makeDTO(id: "m2", thread: "t2", labels: ["INBOX"], internalDate: "2000", snippet: "b"),
            makeDTO(id: "m3", thread: "t3", labels: ["INBOX"], internalDate: "3000", snippet: "c"),
        ]
        let source = ScriptedSource(pages: [(["m1", "m2", "m3"], "p2")], messages: messages)
        let store = try makeStore()
        let service = BackfillService(source: source, store: store)

        try await service.backfillInbox(maxMessages: 2)

        #expect(source.getCallCount == 2)
        #expect(try store.inboxThreads().count == 2)
    }
}
