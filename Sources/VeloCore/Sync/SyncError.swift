import Foundation

/// Errors surfaced by the sync layer.
public enum SyncError: Error, Equatable {
    /// Incremental sync was requested before a `historyId` baseline exists —
    /// the caller must run a backfill (which establishes the cursor) first.
    case notInitialized
}
