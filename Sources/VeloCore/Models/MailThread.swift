import Foundation
import GRDB

public struct MailThread: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var id: String
    /// Who spoke last in the thread -- what a list row shows. Derived from the
    /// newest message rather than the first, which is what other clients do.
    public var sender: String
    public var snippet: String
    public var lastMessageDate: Date
    public var isUnread: Bool
    public var hasAttachments: Bool
    public var labelIDs: [String]
    /// When a snoozed thread should return to the inbox. `nil` means awake.
    ///
    /// Local rather than a Gmail label: the *label* change is what syncs, while
    /// the wake time is this client's business. Gmail's own snooze is not in the
    /// public API.
    public var snoozedUntil: Date?

    public static let databaseTableName = "thread"

    public init(id: String, sender: String = "", snippet: String, lastMessageDate: Date,
                isUnread: Bool, hasAttachments: Bool, labelIDs: [String],
                snoozedUntil: Date? = nil) {
        self.id = id
        self.sender = sender
        self.snippet = snippet
        self.lastMessageDate = lastMessageDate
        self.isUnread = isUnread
        self.hasAttachments = hasAttachments
        self.labelIDs = labelIDs
        self.snoozedUntil = snoozedUntil
    }
}
