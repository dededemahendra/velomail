import Foundation
import GRDB

/// The kind of outbound change queued for the Gmail API.
public enum MutationKind: String, Codable, Equatable, Sendable {
    case archive
    case markRead
    case markUnread
    /// An outgoing message. Unlike the label kinds, its payload is an
    /// `OutboundSendPayload`, not an `OutboundMutationPayload`.
    case send
    /// Removes INBOX so a snooze is visible on every device.
    case snooze
    /// Puts INBOX back when the thread wakes.
    case unsnooze
    /// Adds Gmail's own `STARRED` label. A star is a label, not a local flag,
    /// so it is the same queue, the same push and the same revert as an archive.
    case star
    /// Removes `STARRED`.
    case unstar
}

/// Lifecycle of a queued mutation. Success removes the row (there is no `done`).
public enum MutationStatus: String, Codable, Equatable, Sendable {
    case pending
    case failed
}

/// A durable outbound mutation: an optimistic local change awaiting push to Gmail.
/// `payload` holds a JSON-encoded `OutboundMutationPayload` (the labels to apply,
/// the affected message ids, and the pre-change state for revert-on-failure).
public struct PendingMutation: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Sendable {
    public var id: Int64?
    public var kind: MutationKind
    public var payload: Data
    public var createdAt: Date
    public var status: MutationStatus
    /// How many times `drain()` has tried and failed to push this mutation.
    /// Persisted rather than counted in memory: the queue is durable so a
    /// restart cannot lose writes, and an in-memory count would reset on every
    /// launch, turning a permanently-failing mutation into an endless loop.
    public var attempts: Int
    /// When this may be pushed. `nil` means immediately.
    ///
    /// One column buys both Undo Send and Send Later: both are simply "do not
    /// send this yet", and the drain skips anything not yet due.
    public var dueAt: Date?

    public static let databaseTableName = "pendingMutation"

    public init(id: Int64? = nil, kind: MutationKind, payload: Data,
                createdAt: Date, status: MutationStatus = .pending, attempts: Int = 0,
                dueAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.status = status
        self.attempts = attempts
        self.dueAt = dueAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
