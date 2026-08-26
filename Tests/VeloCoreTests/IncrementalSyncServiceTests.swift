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

private func labelHistoryPage(added: [(id: String, thread: String)] = [],
                              labelsRemoved: [(id: String, labels: [String])] = [],
                              labelsAdded: [(id: String, labels: [String])] = [],
                              historyId: String, nextPageToken: String? = nil) -> GmailHistoryResponse {
    func changesJSON(_ items: [(id: String, labels: [String])]) -> String {
        items.map { item in
            let labels = item.labels.map { "\"\($0)\"" }.joined(separator: ",")
            return "{\"message\":{\"id\":\"\(item.id)\"},\"labelIds\":[\(labels)]}"
        }.joined(separator: ",")
    }
    let addedJSON = added.map { "{\"message\":{\"id\":\"\($0.id)\",\"threadId\":\"\($0.thread)\"}}" }
        .joined(separator: ",")
    var parts = ["\"id\":\"1\""]
    if !added.isEmpty { parts.append("\"messagesAdded\":[\(addedJSON)]") }
    if !labelsRemoved.isEmpty { parts.append("\"labelsRemoved\":[\(changesJSON(labelsRemoved))]") }
    if !labelsAdded.isEmpty { parts.append("\"labelsAdded\":[\(changesJSON(labelsAdded))]") }
    let nextJSON = nextPageToken.map { ",\"nextPageToken\":\"\($0)\"" } ?? ""
    let json = "{\"history\":[{\(parts.joined(separator: ","))}],\"historyId\":\"\(historyId)\"\(nextJSON)}"
    return try! JSONDecoder().decode(GmailHistoryResponse.self, from: Data(json.utf8))
}

/// Scripted history source. Paging restarts on a fresh sync (`pageToken == nil`).
private final class HistorySource: GmailReading, @unchecked Sendable {
    let pages: [GmailHistoryResponse]
    let messages: [String: GmailMessageDTO]
    let notFoundIDs: Set<String>
    private var index = 0
    private(set) var getCallCount = 0
    private(set) var lastStartHistoryId: String?

    init(pages: [GmailHistoryResponse], messages: [GmailMessageDTO], notFoundIDs: Set<String> = []) {
        self.pages = pages
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        self.notFoundIDs = notFoundIDs
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
        if notFoundIDs.contains(id) { throw AuthError.server(code: "NOT_FOUND", description: "deleted") }
        return messages[id]!
    }

    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        fatalError("list not used by incremental sync")
    }

    func getProfile() async throws -> GmailProfile {
        fatalError("getProfile not used by incremental sync")
    }
}

/// Source whose fetchHistory throws a supplied error; used for expiry tests.
private final class ThrowingFetchHistorySource: GmailReading, @unchecked Sendable {
    let error: Error
    private(set) var getCallCount = 0

    init(error: Error) { self.error = error }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        throw error
    }
    func getMessage(id: String) async throws -> GmailMessageDTO {
        getCallCount += 1
        fatalError("getMessage should not be called on history-expired")
    }
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        fatalError("list not used")
    }
    func getProfile() async throws -> GmailProfile { fatalError("getProfile not used") }
}

@Suite struct IncrementalSyncServiceTests {
    private let account = "acct-1"

    private func makeThrowingContext(_ error: Error) throws
        -> (IncrementalSyncService, SyncStateStore, ThrowingFetchHistorySource) {
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let syncStore = SyncStateStore(db)
        try syncStore.save(SyncState(accountID: account, historyId: "1000", backfillComplete: true))
        let source = ThrowingFetchHistorySource(error: error)
        let service = IncrementalSyncService(source: source, store: mailStore, syncState: syncStore)
        return (service, syncStore, source)
    }

    @Test func historyExpired404MapsToSyncError() async throws {
        let (service, _, _) = try makeThrowingContext(AuthError.server(code: "404", description: "gone"))
        await #expect(throws: SyncError.historyExpired) {
            try await service.sync(accountID: account)
        }
    }

    @Test func historyExpiredNotFoundMapsToSyncError() async throws {
        let (service, _, _) = try makeThrowingContext(AuthError.server(code: "NOT_FOUND", description: "gone"))
        await #expect(throws: SyncError.historyExpired) {
            try await service.sync(accountID: account)
        }
    }

    @Test func historyExpiredLeavesCursorUntouched() async throws {
        let (service, syncStore, source) = try makeThrowingContext(AuthError.server(code: "404", description: "gone"))
        await #expect(throws: SyncError.historyExpired) {
            try await service.sync(accountID: account)
        }
        let state = try syncStore.load(accountID: account)
        #expect(state?.historyId == "1000")
        #expect(source.getCallCount == 0)
    }

    @Test func nonExpiryServerErrorPropagatesUnchanged() async throws {
        let (service, _, _) = try makeThrowingContext(AuthError.server(code: "UNAUTHENTICATED", description: "bad"))
        await #expect(throws: AuthError.server(code: "UNAUTHENTICATED", description: "bad")) {
            try await service.sync(accountID: account)
        }
    }

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

    // MARK: - Label deltas end-to-end (C5)

    private func seedMessage(_ store: MailStore, threadID: String, messageID: String, labels: [String]) throws {
        let unread = labels.contains("UNREAD")
        try store.upsert(MailThread(id: threadID, snippet: "s", lastMessageDate: Date(timeIntervalSince1970: 0),
                                    isUnread: unread, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: messageID, threadID: threadID, sender: "", recipients: [], subject: "",
                                 date: Date(timeIntervalSince1970: 0), bodyHTML: nil, bodyText: nil,
                                 isUnread: unread, labelIDs: labels))
    }

    @Test func appliesLabelRemovedToStoredMessage() async throws {
        let (service, mailStore, syncStore, _) = try makeContext(
            pages: [labelHistoryPage(labelsRemoved: [("m1", ["UNREAD"])], historyId: "1100")],
            messages: [], seedHistoryId: "1000")
        try seedMessage(mailStore, threadID: "t1", messageID: "m1", labels: ["INBOX", "UNREAD"])

        try await service.sync(accountID: account)

        #expect(try mailStore.message(id: "m1")?.isUnread == false)
        #expect(try mailStore.thread(id: "t1")?.isUnread == false)
        #expect(try syncStore.load(accountID: account)?.historyId == "1100")
    }

    @Test func labelRemovedInboxArchivesStoredThread() async throws {
        let (service, mailStore, syncStore, _) = try makeContext(
            pages: [labelHistoryPage(labelsRemoved: [("m1", ["INBOX"])], historyId: "1100")],
            messages: [], seedHistoryId: "1000")
        try seedMessage(mailStore, threadID: "t1", messageID: "m1", labels: ["INBOX"])

        try await service.sync(accountID: account)

        #expect(try mailStore.inboxThreads().isEmpty)
        #expect(try syncStore.load(accountID: account)?.historyId == "1100")
    }

    @Test func deltaOnlyPageAdvancesCursorWithoutHydrating() async throws {
        let (service, mailStore, syncStore, source) = try makeContext(
            pages: [labelHistoryPage(labelsRemoved: [("m1", ["UNREAD"])], historyId: "1100")],
            messages: [], seedHistoryId: "1000")
        try seedMessage(mailStore, threadID: "t1", messageID: "m1", labels: ["INBOX", "UNREAD"])

        try await service.sync(accountID: account)

        #expect(source.getCallCount == 0)
        #expect(try syncStore.load(accountID: account)?.historyId == "1100")
    }

    @Test func addedAndLabelDeltaTogetherAreIdempotent() async throws {
        let (service, mailStore, _, _) = try makeContext(
            pages: [labelHistoryPage(added: [("m2", "t2")], labelsAdded: [("m1", ["STARRED"])], historyId: "1100")],
            messages: [makeDTO(id: "m2", thread: "t2", internalDate: "5", snippet: "new")],
            seedHistoryId: "1000")
        try seedMessage(mailStore, threadID: "t1", messageID: "m1", labels: ["INBOX"])

        try await service.sync(accountID: account)
        try await service.sync(accountID: account)   // replay: still stable

        #expect(try mailStore.message(id: "m1")?.labelIDs == ["INBOX", "STARRED"])
        #expect(try mailStore.messages(inThread: "t2").count == 1)
    }

    @Test func skipsDeletedMessageOn404AndAdvancesCursor() async throws {
        // m1 is in history's messagesAdded but 404s on getMessage (deleted/trashed).
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let syncStore = SyncStateStore(db)
        try syncStore.save(SyncState(accountID: account, historyId: "1000", backfillComplete: true))
        let source = HistorySource(
            pages: [historyPage(added: [("m1", "t1")], historyId: "1100", nextPageToken: nil)],
            messages: [], notFoundIDs: ["m1"])
        let service = IncrementalSyncService(source: source, store: mailStore, syncState: syncStore)

        try await service.sync(accountID: account)   // must NOT throw

        #expect(try mailStore.inboxThreads().isEmpty)                     // deleted message skipped
        #expect(try syncStore.load(accountID: account)?.historyId == "1100")  // cursor advances
    }

    @Test func labelDeltaForUnknownMessageIsIgnored() async throws {
        let (service, _, syncStore, _) = try makeContext(
            pages: [labelHistoryPage(labelsAdded: [("ghost", ["X"])], historyId: "1100")],
            messages: [], seedHistoryId: "1000")

        try await service.sync(accountID: account)

        #expect(try syncStore.load(accountID: account)?.historyId == "1100")
    }

    // MARK: - Reporting arrivals (U)

    @Test func syncReportsTheThreadsThatArrived() async throws {
        let (service, _, _, _) = try makeContext(
            pages: [historyPage(added: [("m1", "t1"), ("m2", "t2")],
                                historyId: "5100", nextPageToken: nil)],
            messages: [makeDTO(id: "m1", thread: "t1", internalDate: "1000", snippet: "s"),
                       makeDTO(id: "m2", thread: "t2", internalDate: "1000", snippet: "s")],
            seedHistoryId: "5000")

        let arrived = try await service.sync(accountID: account)

        // Rules need to know what is new; running them over everything would
        // archive mail the user already dealt with.
        #expect(Set(arrived) == ["t1", "t2"])
    }

    @Test func aThreadWithTwoNewMessagesIsReportedOnce() async throws {
        let (service, _, _, _) = try makeContext(
            pages: [historyPage(added: [("m1", "t1"), ("m2", "t1")],
                                historyId: "5100", nextPageToken: nil)],
            messages: [makeDTO(id: "m1", thread: "t1", internalDate: "1000", snippet: "s"),
                       makeDTO(id: "m2", thread: "t1", internalDate: "2000", snippet: "s")],
            seedHistoryId: "5000")

        #expect(try await service.sync(accountID: account) == ["t1"])
    }

    @Test func aQuietSyncReportsNothing() async throws {
        let (service, _, _, _) = try makeContext(
            pages: [historyPage(added: [], historyId: "5100", nextPageToken: nil)],
            messages: [], seedHistoryId: "5000")

        #expect(try await service.sync(accountID: account).isEmpty)
    }
}
