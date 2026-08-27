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

        migrator.registerMigration("v6_add_mutation_attempts") { db in
            try db.alter(table: "pendingMutation") { t in
                t.add(column: "attempts", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v7_add_thread_sender") { db in
            try db.alter(table: "thread") { t in
                t.add(column: "sender", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v8_add_syncstate_email") { db in
            try db.alter(table: "syncState") { t in
                t.add(column: "emailAddress", .text)
            }
        }

        migrator.registerMigration("v9_create_message_search") { db in
            // Standalone FTS5 table, kept in sync by triggers rather than by
            // application code: backfill, incremental sync, optimistic send and
            // revert all write through the same upsert, and none of them should
            // have to know search exists. Triggers make drift impossible.
            //
            // Body comes from bodyText only. Indexing HTML would produce hits
            // on "div" and "span".
            try db.execute(sql: """
                CREATE VIRTUAL TABLE messageSearch USING fts5(
                    id UNINDEXED,
                    threadID UNINDEXED,
                    sender,
                    subject,
                    body,
                    tokenize='porter unicode61'
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER message_search_insert AFTER INSERT ON message BEGIN
                    INSERT INTO messageSearch(id, threadID, sender, subject, body)
                    VALUES (new.id, new.threadID, new.sender, new.subject,
                            coalesce(new.bodyText, ''));
                END
                """)

            // Delete-then-insert rather than UPDATE: sync re-upserts the same
            // message constantly, and an index that duplicates on every write
            // would rot within a day.
            try db.execute(sql: """
                CREATE TRIGGER message_search_update AFTER UPDATE ON message BEGIN
                    DELETE FROM messageSearch WHERE id = old.id;
                    INSERT INTO messageSearch(id, threadID, sender, subject, body)
                    VALUES (new.id, new.threadID, new.sender, new.subject,
                            coalesce(new.bodyText, ''));
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER message_search_delete AFTER DELETE ON message BEGIN
                    DELETE FROM messageSearch WHERE id = old.id;
                END
                """)

            // Backfill what is already stored. Without this, search silently
            // returns nothing for every message that arrived before the upgrade.
            try db.execute(sql: """
                INSERT INTO messageSearch(id, threadID, sender, subject, body)
                SELECT id, threadID, sender, subject, coalesce(bodyText, '') FROM message
                """)
        }

        migrator.registerMigration("v10_add_mutation_dueAt") { db in
            try db.alter(table: "pendingMutation") { t in
                t.add(column: "dueAt", .datetime)
            }
        }

        migrator.registerMigration("v11_add_thread_snoozedUntil") { db in
            try db.alter(table: "thread") { t in
                t.add(column: "snoozedUntil", .datetime)
            }
        }

        // The raw header, not a parsed link: the database stays dumb, and the
        // parsing in `Unsubscribe` can improve without a migration.
        migrator.registerMigration("v12_add_message_listUnsubscribe") { db in
            try db.alter(table: "message") { t in
                t.add(column: "listUnsubscribe", .text)
            }
        }

        migrator.registerMigration("v13_create_attachment") { db in
            try db.create(table: "attachment") { t in
                t.primaryKey("id", .text)
                t.column("messageID", .text).notNull()
                    .references("message", onDelete: .cascade)
                t.column("filename", .text).notNull().defaults(to: "")
                t.column("mimeType", .text).notNull().defaults(to: "application/octet-stream")
                t.column("size", .integer).notNull().defaults(to: 0)
                t.column("attachmentID", .text)
                t.column("inlineData", .text)
            }
            try db.create(index: "attachment_on_messageID", on: "attachment", columns: ["messageID"])
        }

        migrator.registerMigration("v14_create_draft") { db in
            // A single row, keyed by a fixed id: one draft slot rather than a
            // folder, so saving is an upsert and nothing accumulates.
            try db.create(table: "draft") { t in
                t.primaryKey("id", .text)
                t.column("payload", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v15_create_attachment_search") { db in
            // A second index rather than folding filenames into messageSearch:
            // attachments are written *after* their message, so a trigger on
            // `message` cannot see them.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE attachmentSearch USING fts5(
                    messageID UNINDEXED,
                    filename,
                    tokenize='porter unicode61'
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER attachment_search_insert AFTER INSERT ON attachment BEGIN
                    INSERT INTO attachmentSearch(rowid, messageID, filename)
                    VALUES (new.rowid, new.messageID, new.filename);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER attachment_search_update AFTER UPDATE ON attachment BEGIN
                    DELETE FROM attachmentSearch WHERE rowid = old.rowid;
                    INSERT INTO attachmentSearch(rowid, messageID, filename)
                    VALUES (new.rowid, new.messageID, new.filename);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER attachment_search_delete AFTER DELETE ON attachment BEGIN
                    DELETE FROM attachmentSearch WHERE rowid = old.rowid;
                END
                """)

            // Index what is already stored, or attachment search silently
            // returns nothing for every file received before this upgrade.
            try db.execute(sql: """
                INSERT INTO attachmentSearch(rowid, messageID, filename)
                SELECT rowid, messageID, filename FROM attachment
                """)
        }


        migrator.registerMigration("v16_add_attachment_contentID") { db in
            // Nullable and unbackfilled: a `cid:` reference in an already-synced
            // message simply stays unresolved until that message is next
            // hydrated, which is cheaper than re-fetching the whole mailbox.
            try db.alter(table: "attachment") { t in
                t.add(column: "contentID", .text)
            }
        }


        migrator.registerMigration("v17_add_syncstate_backfilledLabels") { db in
            try db.alter(table: "syncState") { t in
                t.add(column: "backfilledLabels", .text)
            }
            // An account that finished a backfill before labels were tracked
            // pulled INBOX and nothing else. Claiming it had done everything is
            // what left the Sent list working and empty; claiming it had done
            // nothing would re-fetch a mailbox it already has.
            try db.execute(sql: """
                UPDATE syncState SET backfilledLabels = '["INBOX"]' WHERE backfillComplete = 1
                """)
        }

        migrator.registerMigration("v18_add_syncstate_olderCursors") { db in
            // Left NULL: an account synced before this has no record of where
            // its listing stopped, so there is nothing honest to claim and
            // "load older" simply starts from the next full pass.
            try db.alter(table: "syncState") { t in
                t.add(column: "olderCursors", .text)
            }
        }


        migrator.registerMigration("v19_create_label") { db in
            // Names only. Which threads carry a label is already on the thread,
            // and a join table would be a second copy of that to keep in step.
            try db.create(table: "label") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
            }
        }


        migrator.registerMigration("v20_add_draft_remoteID") { db in
            // Which Gmail draft a local one was pushed to. Nullable: a draft
            // written here has none until it goes up, and one pulled down is
            // identified by its row id instead.
            try db.alter(table: "draft") { t in
                t.add(column: "remoteID", .text)
            }
        }

        return migrator
    }
}
