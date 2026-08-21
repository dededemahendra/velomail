import Foundation

/// What the sync engine is doing, for the "offline / syncing" indicator the v1
/// design asks for.
///
/// `offline` carries the consecutive-failure count rather than a computed retry
/// time so the value stays a plain fact about what happened; turning it into a
/// delay is `BackoffPolicy`'s job, and keeping them apart means the status is
/// still meaningful to a caller that schedules its own retries.
public enum SyncStatus: Equatable, Sendable {
    /// No pass has run yet.
    case idle
    case syncing
    case upToDate(lastSyncedAt: Date)
    /// The last pass failed transiently; the engine will retry.
    case offline(consecutiveFailures: Int)
}
