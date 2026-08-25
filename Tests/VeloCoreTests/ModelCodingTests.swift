import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct ModelCodingTests {
    @Test func threadRoundTripsWithLabelArray() throws {
        let db = try AppDatabase.makeInMemory()
        let thread = MailThread(
            id: "t1", snippet: "hello",
            lastMessageDate: Date(timeIntervalSince1970: 1000),
            isUnread: true, hasAttachments: false,
            labelIDs: ["INBOX", "Label_5"]
        )
        try db.dbQueue.write { try thread.insert($0) }
        let fetched = try db.dbQueue.read { try MailThread.fetchOne($0, key: "t1") }
        #expect(fetched == thread)
        #expect(fetched?.labelIDs == ["INBOX", "Label_5"])
    }

    @Test func messageRoundTrips() throws {
        let db = try AppDatabase.makeInMemory()
        let thread = MailThread(id: "t1", snippet: "", lastMessageDate: Date(timeIntervalSince1970: 0),
                                isUnread: false, hasAttachments: false, labelIDs: [])
        try db.dbQueue.write { try thread.insert($0) }
        let msg = Message(
            id: "m1", threadID: "t1", sender: "a@b.com",
            recipients: ["c@d.com"], subject: "hi",
            date: Date(timeIntervalSince1970: 10),
            bodyHTML: "<p>hi</p>", bodyText: "hi", isUnread: true,
            labelIDs: ["INBOX", "UNREAD"]
        )
        try db.dbQueue.write { try msg.insert($0) }
        let fetched = try db.dbQueue.read { try Message.fetchOne($0, key: "m1") }
        #expect(fetched == msg)
        #expect(fetched?.labelIDs == ["INBOX", "UNREAD"])
    }

    @Test func aMessageRoundTripsItsListUnsubscribeHeader() throws {
        let db = try AppDatabase.makeInMemory()
        let thread = MailThread(id: "t1", snippet: "", lastMessageDate: Date(timeIntervalSince1970: 0),
                                isUnread: false, hasAttachments: false, labelIDs: [])
        try db.dbQueue.write { try thread.insert($0) }
        let header = "<https://x.example/u/1>, <mailto:leave@x.example>"
        let msg = Message(id: "m1", threadID: "t1", sender: "a@b.com", recipients: [],
                          subject: "", date: Date(timeIntervalSince1970: 10),
                          bodyHTML: nil, bodyText: nil, isUnread: false, labelIDs: [],
                          listUnsubscribe: header)
        try db.dbQueue.write { try msg.insert($0) }

        let fetched = try db.dbQueue.read { try Message.fetchOne($0, key: "m1") }
        // The raw header, not a parsed link: the database stays dumb and the
        // parser can improve without a migration.
        #expect(fetched?.listUnsubscribe == header)
    }

    @Test func messageRoundTripsReplyHeaders() throws {
        let db = try AppDatabase.makeInMemory()
        let thread = MailThread(id: "t1", snippet: "", lastMessageDate: Date(timeIntervalSince1970: 0),
                                isUnread: false, hasAttachments: false, labelIDs: [])
        try db.dbQueue.write { try thread.insert($0) }
        let msg = Message(
            id: "m1", threadID: "t1", sender: "a@b.com", recipients: ["c@d.com"],
            cc: ["e@f.com"], subject: "hi", date: Date(timeIntervalSince1970: 10),
            bodyHTML: nil, bodyText: "hi", isUnread: false, labelIDs: ["SENT"],
            messageIDHeader: "<mine@x.com>", inReplyTo: "<parent@x.com>",
            references: ["<root@x.com>", "<parent@x.com>"]
        )
        try db.dbQueue.write { try msg.insert($0) }
        let fetched = try db.dbQueue.read { try Message.fetchOne($0, key: "m1") }
        #expect(fetched == msg)
        #expect(fetched?.cc == ["e@f.com"])
        #expect(fetched?.references == ["<root@x.com>", "<parent@x.com>"])
    }
}
