import Foundation
import GRDB

/// A draft as it sits on disk, with its row's id and when it was last touched.
public struct StoredDraft: Equatable, Sendable, Identifiable {
    public let id: String
    public let draft: Draft
    public let updatedAt: Date

    public init(id: String, draft: Draft, updatedAt: Date) {
        self.id = id
        self.draft = draft
        self.updatedAt = updatedAt
    }
}

/// Persists the messages being written.
///
/// Originally one slot on the reasoning that a client with one compose window
/// has only one draft to manage. That was wrong in the way that costs work:
/// leaving a half-written reply and starting anything else overwrote it, with
/// no warning and no way back. Each draft now keeps its own row.
public struct DraftStore: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Writes `draft` to its own row, replacing whatever was there before under
    /// that id and leaving every other draft alone.
    public func save(_ draft: Draft, id: String, at moment: Date = Date()) throws {
        let payload = try JSONEncoder().encode(draft)
        try database.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO draft (id, payload, updatedAt) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload,
                                              updatedAt = excluded.updatedAt
                """, arguments: [id, payload, moment])
        }
    }

    /// Every draft, most recently touched first. `rowid` breaks ties, because
    /// two drafts saved in the same millisecond still have an order the writer
    /// would recognise: the one they touched last.
    public func all() throws -> [StoredDraft] {
        try database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, payload, updatedAt FROM draft ORDER BY updatedAt DESC, rowid DESC
                """).compactMap(Self.decode)
        }
    }

    public func load(id: String) throws -> StoredDraft? {
        try database.dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT id, payload, updatedAt FROM draft WHERE id = ?
                """, arguments: [id]).flatMap(Self.decode)
        }
    }

    /// The one "resume what I was writing" means: the most recently touched.
    public func latest() throws -> StoredDraft? {
        try database.dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT id, payload, updatedAt FROM draft ORDER BY updatedAt DESC, rowid DESC LIMIT 1
                """).flatMap(Self.decode)
        }
    }

    public func discard(id: String) throws {
        _ = try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM draft WHERE id = ?", arguments: [id])
        }
    }

    /// A row that will not decode is skipped rather than thrown: one corrupt
    /// draft must not make the others unreachable.
    private static func decode(_ row: Row) -> StoredDraft? {
        guard let id: String = row["id"], let payload: Data = row["payload"],
              let updatedAt: Date = row["updatedAt"],
              let draft = try? JSONDecoder().decode(Draft.self, from: payload) else { return nil }
        return StoredDraft(id: id, draft: draft, updatedAt: updatedAt)
    }
}
