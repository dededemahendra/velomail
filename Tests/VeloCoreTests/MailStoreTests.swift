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
        // Second upsert of the same id with a changed field must overwrite, not duplicate.
        try store.upsert(thread("t", date: 100, labels: ["INBOX", "SENT"]))
        let inbox = try store.inboxThreads()
        #expect(inbox.count == 1)
        #expect(inbox.first?.labelIDs == ["INBOX", "SENT"])
    }

    @Test func messagesInThreadSortedOldestFirst() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 0, labels: ["INBOX"]))
        try store.upsert(Message(id: "m2", threadID: "t", sender: "x", recipients: [],
                                 subject: "", date: Date(timeIntervalSince1970: 20),
                                 bodyHTML: nil, bodyText: nil, isUnread: false, labelIDs: []))
        try store.upsert(Message(id: "m1", threadID: "t", sender: "x", recipients: [],
                                 subject: "", date: Date(timeIntervalSince1970: 10),
                                 bodyHTML: nil, bodyText: nil, isUnread: false, labelIDs: []))
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

    @Test func threadByIDReturnsStoredOrNil() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 100, labels: ["INBOX"]))
        #expect(try store.thread(id: "t")?.id == "t")
        #expect(try store.thread(id: "missing") == nil)
    }

    @Test func messageByIDReturnsStoredOrNil() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 100, labels: ["INBOX"]))
        try store.upsert(Message(id: "m1", threadID: "t", sender: "", recipients: [], subject: "",
                                 date: Date(timeIntervalSince1970: 1), bodyHTML: nil, bodyText: nil,
                                 isUnread: false, labelIDs: ["INBOX"]))
        #expect(try store.message(id: "m1")?.id == "m1")
        #expect(try store.message(id: "nope") == nil)
    }

    @Test func updateThreadDerivedLabelsPreservesOtherFields() throws {
        let store = try makeStore()
        try store.upsert(MailThread(id: "t", snippet: "keep", lastMessageDate: Date(timeIntervalSince1970: 55),
                                    isUnread: true, hasAttachments: true, labelIDs: ["INBOX", "UNREAD"]))

        try store.updateThreadDerivedLabels(["INBOX"], isUnread: false, onThread: "t")

        let updated = try store.thread(id: "t")
        #expect(updated?.labelIDs == ["INBOX"])
        #expect(updated?.isUnread == false)
        #expect(updated?.snippet == "keep")
        #expect(updated?.lastMessageDate == Date(timeIntervalSince1970: 55))
        #expect(updated?.hasAttachments == true)

        try store.updateThreadDerivedLabels(["X"], isUnread: true, onThread: "ghost")   // no-op
        #expect(try store.thread(id: "ghost") == nil)
    }

    @Test func deleteMessageRemovesOnlyThatMessage() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 100, labels: ["INBOX"]))
        for id in ["m1", "m2"] {
            try store.upsert(Message(id: id, threadID: "t", sender: "a@b.com", recipients: [],
                                     subject: "s", date: Date(timeIntervalSince1970: 100),
                                     bodyHTML: nil, bodyText: nil, isUnread: false, labelIDs: []))
        }

        try store.deleteMessage(id: "m1")

        #expect(try store.message(id: "m1") == nil)
        #expect(try store.message(id: "m2") != nil)
        #expect(try store.thread(id: "t") != nil)
    }

    @Test func deleteThreadRemovesThreadAndItsMessages() throws {
        let store = try makeStore()
        try store.upsert(thread("t", date: 100, labels: ["INBOX"]))
        try store.upsert(Message(id: "m1", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 100),
                                 bodyHTML: nil, bodyText: nil, isUnread: false, labelIDs: []))

        try store.deleteThread(id: "t")

        #expect(try store.thread(id: "t") == nil)
        #expect(try store.message(id: "m1") == nil)
    }

    @Test func deleteMessageIsANoOpForAnUnknownID() throws {
        let store = try makeStore()
        try store.deleteMessage(id: "nope")
        #expect(try store.message(id: "nope") == nil)
    }
}
