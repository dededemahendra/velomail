import Foundation

/// Errors surfaced by the sync layer.
public enum SyncError: Error, Equatable {
    /// Incremental sync was requested before a `historyId` baseline exists —
    /// the caller must run a backfill (which establishes the cursor) first.
    case notInitialized

    /// The stored `startHistoryId` is too old (Gmail returns HTTP 404). The
    /// caller must re-backfill to re-establish a fresh cursor.
    case historyExpired
}
