import Foundation
import GRDB

/// A draft as it sits on disk, with when it was last touched.
public struct StoredDraft: Equatable, Sendable {
    public let draft: Draft
    public let updatedAt: Date
}

/// Persists the message being written.
///
/// One slot, not a folder. A folder implies management -- listing, choosing,
/// deleting -- and a keyboard-first client with one compose window does not have
/// several drafts to manage. Pressing compose resumes what you were writing.
public struct DraftStore: Sendable {
    /// The single row's key. A fixed id is what makes "save" an upsert and keeps
    /// the slot from accumulating.
    private static let slot = "current"

    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func save(_ draft: Draft, at moment: Date = Date()) throws {
        let payload = try JSONEncoder().encode(draft)
        try database.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO draft (id, payload, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload,
                                              updatedAt = excluded.updatedAt
                """, arguments: [Self.slot, payload, moment])
        }
    }

    public func load() throws -> StoredDraft? {
        try database.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT payload, updatedAt FROM draft WHERE id = ?",
                                             arguments: [Self.slot]),
                  let payload: Data = row["payload"],
                  let updatedAt: Date = row["updatedAt"],
                  let draft = try? JSONDecoder().decode(Draft.self, from: payload) else {
                return nil
            }
            return StoredDraft(draft: draft, updatedAt: updatedAt)
        }
    }

    public func discard() throws {
        _ = try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM draft WHERE id = ?", arguments: [Self.slot])
        }
    }
}
