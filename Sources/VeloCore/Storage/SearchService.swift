import Foundation
import GRDB

/// Full-text search over the mailbox, returning threads.
///
/// Threads rather than messages because that is the unit the UI shows and the
/// unit a person is looking for; a thread matches if any of its messages does.
public struct SearchService: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func search(_ query: SearchQuery, limit: Int = 200) throws -> [MailThread] {
        try database.dbQueue.read { db in
            var conditions: [String] = []
            var arguments: [DatabaseValueConvertible?] = []

            // User input never reaches SQL directly: FTS5 has its own query
            // syntax, so a stray quote or star in a search box would be a
            // syntax error. FTS5Pattern is what makes arbitrary typing safe.
            if let pattern = FTS5Pattern(matchingAllTokensIn: query.terms) {
                // A thread matches on its text *or* on the name of a file
                // attached to it -- the whole reason for attaching something is
                // that you go looking for it later.
                conditions.append("""
                    (message.id IN (SELECT id FROM messageSearch WHERE messageSearch MATCH ?)
                     OR message.id IN (SELECT messageID FROM attachmentSearch
                                       WHERE attachmentSearch MATCH ?))
                    """)
                arguments.append(pattern)
                arguments.append(pattern)
            }

            if let from = query.from, !from.isEmpty {
                conditions.append("lower(message.sender) LIKE ?")
                arguments.append("%\(from.lowercased())%")
            }
            if let isUnread = query.isUnread {
                conditions.append("thread.isUnread = ?")
                arguments.append(isUnread)
            }
            if let after = query.after {
                conditions.append("thread.lastMessageDate >= ?")
                arguments.append(after)
            }
            if let before = query.before {
                conditions.append("thread.lastMessageDate <= ?")
                arguments.append(before)
            }
            if let hasAttachment = query.hasAttachment {
                // The thread's own flag, not a join against the attachment
                // table: parts are fetched on demand, so a thread is known to
                // carry a file long before any row describes it, and joining
                // would hide exactly the mail being looked for.
                conditions.append("thread.hasAttachments = ?")
                arguments.append(hasAttachment)
            }
            if let filename = query.filename, !filename.isEmpty {
                // LIKE rather than the FTS index: people search for "invoice"
                // meaning `2026-invoice-final.pdf`, and FTS5 matches tokens,
                // not fragments of them.
                conditions.append("""
                    message.id IN (SELECT messageID FROM attachment
                                   WHERE lower(filename) LIKE ?)
                    """)
                arguments.append("%\(filename.lowercased())%")
            }

            let whereClause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
            arguments.append(limit)

            // DISTINCT because several messages in one thread may match, and the
            // thread should appear once.
            let sql = """
                SELECT DISTINCT thread.* FROM thread
                JOIN message ON message.threadID = thread.id\(whereClause)
                ORDER BY thread.lastMessageDate DESC
                LIMIT ?
                """
            return try MailThread.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }
}
