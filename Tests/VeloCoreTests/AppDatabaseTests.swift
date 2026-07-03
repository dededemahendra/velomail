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
}
