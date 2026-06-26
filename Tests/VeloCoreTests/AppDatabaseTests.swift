import Testing
import GRDB
@testable import VeloCore

@Suite struct AppDatabaseTests {
    @Test func migrationsCreateTables() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let hasThread = try db.tableExists("thread")
            let hasMessage = try db.tableExists("message")
            #expect(hasThread)
            #expect(hasMessage)
        }
    }
}
