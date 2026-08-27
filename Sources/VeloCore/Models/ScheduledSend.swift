import Foundation

/// A message written, finished, and waiting for its hour.
public struct ScheduledSend: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let draft: Draft
    public let dueAt: Date

    public init(id: Int64, draft: Draft, dueAt: Date) {
        self.id = id
        self.draft = draft
        self.dueAt = dueAt
    }
}
