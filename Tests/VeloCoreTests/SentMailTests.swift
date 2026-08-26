import Testing
import Foundation
@testable import VeloCore

@Suite struct SentMailTests {
    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    private func seed(_ store: MailStore, id: String, labels: [String],
                      at seconds: TimeInterval) throws {
        try store.upsert(MailThread(id: id, sender: "Alice <alice@x.com>", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: seconds),
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
    }

    // MARK: - The query

    @Test func sentThreadsAreTheOnesGmailLabelledSent() throws {
        let store = try makeStore()
        try seed(store, id: "in", labels: ["INBOX"], at: 10)
        try seed(store, id: "out", labels: ["SENT"], at: 20)

        #expect(try store.sentThreads().map(\.id) == ["out"])
    }

    @Test func theNewestSentThreadComesFirst() throws {
        let store = try makeStore()
        try seed(store, id: "old", labels: ["SENT"], at: 10)
        try seed(store, id: "new", labels: ["SENT"], at: 30)

        #expect(try store.sentThreads().map(\.id) == ["new", "old"])
    }

    @Test func aThreadYouRepliedInIsInBothPlaces() throws {
        // Gmail keeps INBOX and SENT on the same thread, and so must we: a
        // conversation should not leave the inbox because you answered it.
        let store = try makeStore()
        try seed(store, id: "t", labels: ["INBOX", "SENT"], at: 10)

        #expect(try store.inboxThreads().map(\.id) == ["t"])
        #expect(try store.sentThreads().map(\.id) == ["t"])
    }

    @Test func snoozingDoesNotHideSentMail() throws {
        // A snooze is about when something should come back to the inbox. It
        // has nothing to say about what you have already sent.
        let store = try makeStore()
        try seed(store, id: "t", labels: ["SENT"], at: 10)
        try store.setSnoozedUntil(Date(timeIntervalSince1970: 9_999), onThread: "t")

        #expect(try store.sentThreads().map(\.id) == ["t"])
    }

    // MARK: - Getting it there

    @Test func backfillFetchesSentAsWellAsInbox() async throws {
        let source = LabelledSource(pages: [
            "INBOX": ["i1"],
            "SENT": ["s1"],
        ])
        let store = try makeStore()
        let db = try AppDatabase.makeInMemory()
        let service = BackfillService(source: source, store: store,
                                      syncState: SyncStateStore(db))

        try await service.backfillInbox(accountID: "me@x.com", maxMessages: 50)

        #expect(source.requestedLabels.sorted() == ["INBOX", "SENT"])
        #expect(try store.inboxThreads().map(\.id) == ["t-i1"])
        #expect(try store.sentThreads().map(\.id) == ["t-s1"])
    }

    @Test func aMessageInBothLabelsIsFetchedOnce() async throws {
        // history.list and the two label passes overlap on a replied thread.
        let source = LabelledSource(pages: ["INBOX": ["m"], "SENT": ["m"]])
        let store = try makeStore()
        let db = try AppDatabase.makeInMemory()
        let service = BackfillService(source: source, store: store,
                                      syncState: SyncStateStore(db))

        try await service.backfillInbox(accountID: "me@x.com", maxMessages: 50)

        #expect(source.fetchedIDs == ["m"])
    }
}

/// A source that serves a different id list per label.
private final class LabelledSource: GmailReading, @unchecked Sendable {
    private let pages: [String: [String]]
    private(set) var requestedLabels: [String] = []
    private(set) var fetchedIDs: [String] = []

    init(pages: [String: [String]]) { self.pages = pages }

    func getProfile() async throws -> GmailProfile {
        GmailProfile(emailAddress: "me@x.com", historyId: "1")
    }

    func listMessageIDs(labelID: String, pageToken: String?)
        async throws -> (ids: [String], nextPageToken: String?) {
        requestedLabels.append(labelID)
        return (pages[labelID] ?? [], nil)
    }

    func getMessage(id: String) async throws -> GmailMessageDTO {
        fetchedIDs.append(id)
        let label = id.hasPrefix("s") ? "SENT" : "INBOX"
        let json = """
        {"id":"\(id)","threadId":"t-\(id)","labelIds":["\(label)"],"snippet":"s",
         "internalDate":"1000",
         "payload":{"mimeType":"text/plain",
           "headers":[{"name":"From","value":"a@b.com"},{"name":"Subject","value":"s"}],
           "body":{"data":"cGxhaW4gYm9keQ"}}}
        """
        return try JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
    }

    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError("history not used by backfill")
    }
}
