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
    /// How many messages the thread holds. Stored rather than counted on
    /// demand: a list row cannot afford a query each.
    public var messageCount: Int
    /// How many people the newest message went to, To and Cc together. One
    /// means it was written to you and nobody else.
    public var recipientCount: Int
    /// When a snoozed thread should return to the inbox. `nil` means awake.
    ///
    /// Local rather than a Gmail label: the *label* change is what syncs, while
    /// the wake time is this client's business. Gmail's own snooze is not in the
    /// public API.
    public var snoozedUntil: Date?

    public static let databaseTableName = "thread"

    public init(id: String, sender: String = "", snippet: String, lastMessageDate: Date,
                isUnread: Bool, hasAttachments: Bool, labelIDs: [String],
                messageCount: Int = 1, recipientCount: Int = 0,
                snoozedUntil: Date? = nil) {
        self.id = id
        self.sender = sender
        self.snippet = snippet
        self.lastMessageDate = lastMessageDate
        self.isUnread = isUnread
        self.hasAttachments = hasAttachments
        self.labelIDs = labelIDs
        self.messageCount = messageCount
        self.recipientCount = recipientCount
        self.snoozedUntil = snoozedUntil
    }
}
