import Foundation
import GRDB

/// Persists the per-account `SyncState` (Gmail history cursor + backfill flag).
public final class SyncStateStore {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func load(accountID: String) throws -> SyncState? {
        try database.dbQueue.read { try SyncState.fetchOne($0, key: accountID) }
    }

    public func save(_ state: SyncState) throws {
        try database.dbQueue.write { try state.save($0) }
    }
}
