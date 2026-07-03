import Foundation
import GRDB

/// Durable FIFO queue of outbound `PendingMutation`s. Ordering is by
/// autoincrement `id`. Success removes a row; failure flips it to `.failed`.
public final class MutationStore {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts a mutation and returns it with its assigned `id` populated.
    public func enqueue(_ mutation: PendingMutation) throws -> PendingMutation {
        try database.dbQueue.write { db in
            var m = mutation
            try m.insert(db)
            return m
        }
    }

    /// Pending mutations, oldest first (FIFO by id).
    public func pending() throws -> [PendingMutation] {
        try database.dbQueue.read { db in
            try PendingMutation
                .filter(Column("status") == MutationStatus.pending.rawValue)
                .order(Column("id").asc)
                .fetchAll(db)
        }
    }

    /// All mutations regardless of status, oldest first.
    public func all() throws -> [PendingMutation] {
        try database.dbQueue.read { db in
            try PendingMutation.order(Column("id").asc).fetchAll(db)
        }
    }

    /// Marks a mutation failed (keeps the row). No-op if the id is unknown.
    public func markFailed(id: Int64) throws {
        try database.dbQueue.write { db in
            guard var mutation = try PendingMutation.fetchOne(db, key: id) else { return }
            mutation.status = .failed
            try mutation.update(db)
        }
    }

    /// Removes a mutation (models "done"). No-op if the id is unknown.
    public func delete(id: Int64) throws {
        _ = try database.dbQueue.write { db in
            try PendingMutation.deleteOne(db, key: id)
        }
    }
}
