import Foundation
import GRDB

/// Owns the SQLite connection and applies schema migrations.
public final class AppDatabase {
    public let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    public static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue())
    }

    public static func make(atPath path: String) throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue(path: path))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_thread_and_message") { db in
            try db.create(table: "thread") { t in
                t.primaryKey("id", .text)
                t.column("snippet", .text).notNull().defaults(to: "")
                t.column("lastMessageDate", .datetime).notNull()
                t.column("isUnread", .boolean).notNull().defaults(to: false)
                t.column("hasAttachments", .boolean).notNull().defaults(to: false)
                t.column("labelIDs", .text).notNull().defaults(to: "[]")
            }

            try db.create(table: "message") { t in
                t.primaryKey("id", .text)
                t.column("threadID", .text).notNull()
                    .references("thread", onDelete: .cascade)
                t.column("sender", .text).notNull().defaults(to: "")
                t.column("recipients", .text).notNull().defaults(to: "[]")
                t.column("subject", .text).notNull().defaults(to: "")
                t.column("date", .datetime).notNull()
                t.column("bodyHTML", .text)
                t.column("bodyText", .text)
                t.column("isUnread", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "message_on_threadID", on: "message", columns: ["threadID"])
        }

        return migrator
    }
}
