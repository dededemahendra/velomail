import Foundation
import GRDB

/// Owns the SQLite connection and applies schema migrations.
public final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

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

        migrator.registerMigration("v2_create_sync_state") { db in
            try db.create(table: "syncState") { t in
                t.primaryKey("accountID", .text)
                t.column("historyId", .text)
                t.column("backfillComplete", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v3_create_pending_mutation") { db in
            try db.create(table: "pendingMutation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
            }
            try db.create(index: "pendingMutation_on_status", on: "pendingMutation", columns: ["status"])
        }

        migrator.registerMigration("v4_add_message_labelIDs") { db in
            try db.alter(table: "message") { t in
                t.add(column: "labelIDs", .text).notNull().defaults(to: "[]")
            }
        }

        migrator.registerMigration("v5_add_message_reply_headers") { db in
            try db.alter(table: "message") { t in
                t.add(column: "cc", .text).notNull().defaults(to: "[]")
                t.add(column: "messageIDHeader", .text)
                t.add(column: "inReplyTo", .text)
                t.add(column: "references", .text).notNull().defaults(to: "[]")
            }
        }

        return migrator
    }
}
