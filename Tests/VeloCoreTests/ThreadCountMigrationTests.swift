import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct ThreadCountMigrationTests {
    @Test func existingThreadsAreCountedRatherThanLeftAtOne() throws {
        // Without the backfill every thread already on disk reads as one
        // message until it happens to be re-synced, which for old mail is
        // never.
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t1", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(), isUnread: false,
                                    hasAttachments: false, labelIDs: ["INBOX"]))
        for i in 0..<4 {
            try store.upsert(Message(id: "m\(i)", threadID: "t1", sender: "a@b.com",
                                     recipients: ["me@x.com", "other@x.com"],
                                     cc: ["third@x.com"],
                                     subject: "s", date: Date(timeIntervalSince1970: Double(i)),
                                     bodyHTML: nil, bodyText: "b", isUnread: false,
                                     labelIDs: []))
        }
        // Re-run what the migration does, against rows inserted after it.
        try db.dbQueue.write { database in
            try database.execute(sql: """
                UPDATE thread SET messageCount = MAX(1, (
                    SELECT COUNT(*) FROM message WHERE message.threadID = thread.id
                ))
                """)
            try database.execute(sql: """
                UPDATE thread SET recipientCount = COALESCE((
                    SELECT json_array_length(m.recipients) + json_array_length(m.cc)
                    FROM message m WHERE m.threadID = thread.id
                    ORDER BY m.date DESC LIMIT 1
                ), 0)
                """)
        }

        let thread = try #require(try store.thread(id: "t1"))
        #expect(thread.messageCount == 4)
        #expect(thread.recipientCount == 3)
    }

    @Test func aThreadWithNoMessagesStaysAtOneRatherThanZero() throws {
        // MAX(1, ...) so an orphaned thread row does not read as empty.
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t2", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(), isUnread: false,
                                    hasAttachments: false, labelIDs: ["INBOX"]))
        try db.dbQueue.write { database in
            try database.execute(sql: """
                UPDATE thread SET messageCount = MAX(1, (
                    SELECT COUNT(*) FROM message WHERE message.threadID = thread.id
                ))
                """)
        }
        #expect(try store.thread(id: "t2")?.messageCount == 1)
    }

    @Test func theMapperCountsWhatItWasGiven() {
        let dtos = (0..<3).map { i in
            GmailMessageDTO(id: "m\(i)", threadId: "t", labelIds: ["INBOX"],
                            snippet: "s", internalDate: "1700000000000", payload: nil)
        }
        let thread = try! #require(GmailMessageMapper.thread(from: dtos))
        #expect(thread.messageCount == 3)
    }
}
