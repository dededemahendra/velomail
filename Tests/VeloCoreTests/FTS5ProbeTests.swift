import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct FTS5ProbeTests {
    @Test func fts5IsAvailableInThisSQLiteBuild() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE probe USING fts5(body, tokenize='porter unicode61')
                """)
            try db.execute(sql: "INSERT INTO probe(body) VALUES ('the running foxes')")
            let hits = try Int.fetchOne(db, sql: "SELECT count(*) FROM probe WHERE probe MATCH ?",
                                        arguments: ["run"]) ?? 0
            // Porter stemming should match "running" from "run".
            #expect(hits == 1)
        }
    }
}

@Suite struct MessageSearchIndexTests {
    private func makeStore() throws -> (MailStore, AppDatabase) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        return (store, db)
    }

    private func message(_ id: String, subject: String = "Plot map",
                         body: String = "the eastern boundary needs redrawing",
                         sender: String = "Salsa <salsa@example.com>") -> Message {
        Message(id: id, threadID: "t", sender: sender, recipients: [], subject: subject,
                date: Date(timeIntervalSince1970: 1), bodyHTML: nil, bodyText: body,
                isUnread: false, labelIDs: ["INBOX"])
    }

    private func indexedRows(_ db: AppDatabase) throws -> Int {
        try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM messageSearch") ?? 0 }
    }

    @Test func theIndexTableExists() throws {
        let (_, db) = try makeStore()
        #expect(try indexedRows(db) == 0)
    }

    @Test func insertingAMessageIndexesIt() throws {
        let (store, db) = try makeStore()
        try store.upsert(message("m1"))
        #expect(try indexedRows(db) == 1)
    }

    @Test func deletingAMessageRemovesItFromTheIndex() throws {
        let (store, db) = try makeStore()
        try store.upsert(message("m1"))
        try store.deleteMessage(id: "m1")
        #expect(try indexedRows(db) == 0)
    }

    @Test func updatingAMessageDoesNotDuplicateItInTheIndex() throws {
        let (store, db) = try makeStore()
        try store.upsert(message("m1", body: "first version"))
        try store.upsert(message("m1", body: "second version"))

        // Sync re-upserts constantly; a duplicating index would rot fast.
        #expect(try indexedRows(db) == 1)
        let hits = try db.dbQueue.read {
            try String.fetchAll($0, sql: "SELECT body FROM messageSearch")
        }
        #expect(hits == ["second version"])
    }

    @Test func deletingAThreadCascadesOutOfTheIndex() throws {
        let (store, db) = try makeStore()
        try store.upsert(message("m1"))
        try store.deleteThread(id: "t")
        #expect(try indexedRows(db) == 0)
    }

    @Test func senderAndSubjectAreIndexedAlongsideTheBody() throws {
        let (store, db) = try makeStore()
        try store.upsert(message("m1"))
        let row = try db.dbQueue.read {
            try Row.fetchOne($0, sql: "SELECT sender, subject, body FROM messageSearch")
        }
        #expect((row?["sender"] as String?)?.contains("Salsa") == true)
        #expect(row?["subject"] as String? == "Plot map")
    }

    @Test func aMessageWithNoTextBodyStillIndexesItsSubject() throws {
        let (store, db) = try makeStore()
        var html = message("m1", body: "")
        html.bodyText = nil
        html.bodyHTML = "<p>markup only</p>"
        try store.upsert(html)

        // Indexing markup would produce hits on "div"; the subject still works.
        #expect(try indexedRows(db) == 1)
        let body = try db.dbQueue.read {
            try String.fetchOne($0, sql: "SELECT body FROM messageSearch")
        }
        #expect(body == "")
    }
}
