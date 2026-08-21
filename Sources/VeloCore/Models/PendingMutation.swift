import Foundation
import GRDB

/// The kind of outbound change queued for the Gmail API.
public enum MutationKind: String, Codable, Equatable {
    case archive
    case markRead
    case markUnread
    /// An outgoing message. Unlike the label kinds, its payload is an
    /// `OutboundSendPayload`, not an `OutboundMutationPayload`.
    case send
}

/// Lifecycle of a queued mutation. Success removes the row (there is no `done`).
public enum MutationStatus: String, Codable, Equatable {
    case pending
    case failed
}

/// A durable outbound mutation: an optimistic local change awaiting push to Gmail.
/// `payload` holds a JSON-encoded `OutboundMutationPayload` (the labels to apply,
/// the affected message ids, and the pre-change state for revert-on-failure).
public struct PendingMutation: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
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

    public static let databaseTableName = "pendingMutation"

    public init(id: Int64? = nil, kind: MutationKind, payload: Data,
                createdAt: Date, status: MutationStatus = .pending, attempts: Int = 0) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.status = status
        self.attempts = attempts
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
