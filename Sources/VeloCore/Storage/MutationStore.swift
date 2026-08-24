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

    /// Pending mutations that are due, oldest first (FIFO by id).
    ///
    /// A null `dueAt` means "now", so the label kinds -- which never
    /// schedule -- are unaffected.
    public func pending(due now: Date = Date()) throws -> [PendingMutation] {
        try database.dbQueue.read { db in
            try PendingMutation
                .filter(Column("status") == MutationStatus.pending.rawValue)
                .filter(sql: "dueAt IS NULL OR dueAt <= ?", arguments: [now])
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

    /// Marks a mutation failed and counts the attempt (keeps the row).
    /// No-op if the id is unknown.
    public func markFailed(id: Int64) throws {
        try database.dbQueue.write { db in
            guard var mutation = try PendingMutation.fetchOne(db, key: id) else { return }
            mutation.status = .failed
            mutation.attempts += 1
            try mutation.update(db)
        }
    }

    /// Returns failed mutations to the queue so the next drain retries them,
    /// but only while they are under `maxAttempts`. Rows at the cap stay
    /// `.failed`, which is what stops a deterministically-broken write (a
    /// malformed send, say) from being retried on every tick forever.
    /// `attempts` is deliberately not reset, so the cap survives a requeue.
    public func retryFailed(maxAttempts: Int) throws {
        try database.dbQueue.write { db in
            let retryable = try PendingMutation
                .filter(Column("status") == MutationStatus.failed.rawValue)
                .filter(Column("attempts") < maxAttempts)
                .fetchAll(db)
            for var mutation in retryable {
                mutation.status = .pending
                try mutation.update(db)
            }
        }
    }

    /// Removes a mutation (models "done"). No-op if the id is unknown.
    public func delete(id: Int64) throws {
        _ = try database.dbQueue.write { db in
            try PendingMutation.deleteOne(db, key: id)
        }
    }
}
