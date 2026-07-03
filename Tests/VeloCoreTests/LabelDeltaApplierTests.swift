import Testing
import Foundation
@testable import VeloCore

@Suite struct LabelDeltaApplierTests {
    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    /// Seeds a thread and its messages with derived thread aggregates.
    private func seed(_ store: MailStore, threadID: String, messages: [(id: String, labels: [String])]) throws {
        let msgs = messages.map {
            Message(id: $0.id, threadID: threadID, sender: "", recipients: [], subject: "",
                    date: Date(timeIntervalSince1970: 0), bodyHTML: nil, bodyText: nil,
                    isUnread: $0.labels.contains("UNREAD"), labelIDs: $0.labels)
        }
        let (labels, unread) = GmailMessageMapper.threadAggregate(from: msgs)
        try store.upsert(MailThread(id: threadID, snippet: "s", lastMessageDate: Date(timeIntervalSince1970: 0),
                                    isUnread: unread, hasAttachments: false, labelIDs: labels))
        for m in msgs { try store.upsert(m) }
    }

    @Test func removeUnreadFromOnlyMessageClearsThreadUnread() throws {
        let store = try makeStore()
        try seed(store, threadID: "t", messages: [("m1", ["INBOX", "UNREAD"])])

        try LabelDeltaApplier.apply([.init(messageID: "m1", added: [], removed: ["UNREAD"])], into: store)

        #expect(try store.message(id: "m1")?.labelIDs == ["INBOX"])
        #expect(try store.message(id: "m1")?.isUnread == false)
        #expect(try store.thread(id: "t")?.isUnread == false)
    }

    @Test func removeInboxFromAllMessagesArchivesThread() throws {
        let store = try makeStore()
        try seed(store, threadID: "t", messages: [("m1", ["INBOX"]), ("m2", ["INBOX"])])

        try LabelDeltaApplier.apply([
            .init(messageID: "m1", added: [], removed: ["INBOX"]),
            .init(messageID: "m2", added: [], removed: ["INBOX"]),
        ], into: store)

        #expect(try store.inboxThreads().isEmpty)
    }

    @Test func removingUnreadFromOneOfTwoKeepsThreadUnread() throws {
        let store = try makeStore()
        try seed(store, threadID: "t", messages: [("m1", ["INBOX", "UNREAD"]), ("m2", ["INBOX", "UNREAD"])])

        try LabelDeltaApplier.apply([.init(messageID: "m1", added: [], removed: ["UNREAD"])], into: store)

        #expect(try store.thread(id: "t")?.isUnread == true)   // m2 still unread
    }

    @Test func addLabelUnionsIntoMessageAndThread() throws {
        let store = try makeStore()
        try seed(store, threadID: "t", messages: [("m1", ["INBOX"])])

        try LabelDeltaApplier.apply([.init(messageID: "m1", added: ["Label_9"], removed: [])], into: store)

        #expect(try store.message(id: "m1")?.labelIDs == ["INBOX", "Label_9"])
        #expect(try store.thread(id: "t")?.labelIDs == ["INBOX", "Label_9"])
    }

    @Test func unknownMessageIsNoOp() throws {
        let store = try makeStore()
        try seed(store, threadID: "t", messages: [("m1", ["INBOX"])])

        try LabelDeltaApplier.apply([.init(messageID: "ghost", added: ["X"], removed: [])], into: store)

        #expect(try store.message(id: "m1")?.labelIDs == ["INBOX"])
        #expect(try store.thread(id: "t")?.labelIDs == ["INBOX"])
    }

    @Test func orderedDeltasNetToUnreadPresent() throws {
        let store = try makeStore()
        try seed(store, threadID: "t", messages: [("m1", ["INBOX", "UNREAD"])])

        try LabelDeltaApplier.apply([
            .init(messageID: "m1", added: [], removed: ["UNREAD"]),
            .init(messageID: "m1", added: ["UNREAD"], removed: []),
        ], into: store)

        #expect(try store.message(id: "m1")?.labelIDs.contains("UNREAD") == true)
        #expect(try store.thread(id: "t")?.isUnread == true)
    }
}
