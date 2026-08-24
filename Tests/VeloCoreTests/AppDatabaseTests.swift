import Testing
import GRDB
@testable import VeloCore

@Suite struct AppDatabaseTests {
    @Test func migrationsCreateTables() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let hasThread = try db.tableExists("thread")
            let hasMessage = try db.tableExists("message")
            let hasSyncState = try db.tableExists("syncState")
            let hasPendingMutation = try db.tableExists("pendingMutation")
            let messageColumns = try db.columns(in: "message").map(\.name)
            #expect(hasThread)
            #expect(hasMessage)
            #expect(hasSyncState)
            #expect(hasPendingMutation)
            #expect(messageColumns.contains("labelIDs"))
        }
    }

    @Test func messageTableHasReplyThreadingColumns() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let columns = try db.columns(in: "message").map(\.name)
            #expect(columns.contains("cc"))
            #expect(columns.contains("messageIDHeader"))
            #expect(columns.contains("inReplyTo"))
            #expect(columns.contains("references"))
        }
    }

    @Test func pendingMutationTableHasAttemptsColumn() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let columns = try db.columns(in: "pendingMutation").map(\.name)
            #expect(columns.contains("attempts"))
        }
    }

    @Test func threadTableHasASenderColumn() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let columns = try db.columns(in: "thread").map(\.name)
            #expect(columns.contains("sender"))
        }
    }

    @Test func syncStateTableHasAnEmailAddressColumn() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let columns = try db.columns(in: "syncState").map(\.name)
            #expect(columns.contains("emailAddress"))
        }
    }

    @Test func pendingMutationTableHasADueAtColumn() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let columns = try db.columns(in: "pendingMutation").map(\.name)
            #expect(columns.contains("dueAt"))
        }
    }
}
