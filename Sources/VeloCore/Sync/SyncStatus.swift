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
    /// The last pass failed for a reason retrying is unlikely to fix (a dead
    /// cursor that survived a re-backfill, a storage fault). Kept distinct from
    /// `offline` so a UI can say "something is wrong" rather than "reconnecting".
    case failed(reason: String)
    /// Gmail answered, and refused: the sign-in has run out. Distinct from
    /// `failed` for the same reason `failed` is distinct from `offline` -- this
    /// one has a thing the reader can do about it, and no amount of retrying is
    /// it. A Desktop client in testing mode expires its refresh token after a
    /// week, so this is a state the app will reach in ordinary use.
    case expired
}
