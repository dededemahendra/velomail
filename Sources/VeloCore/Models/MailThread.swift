import Foundation
import GRDB

public struct MailThread: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: String
    public var snippet: String
    public var lastMessageDate: Date
    public var isUnread: Bool
    public var hasAttachments: Bool
    public var labelIDs: [String]

    public static let databaseTableName = "thread"

    public init(id: String, snippet: String, lastMessageDate: Date,
                isUnread: Bool, hasAttachments: Bool, labelIDs: [String]) {
        self.id = id
        self.snippet = snippet
        self.lastMessageDate = lastMessageDate
        self.isUnread = isUnread
        self.hasAttachments = hasAttachments
        self.labelIDs = labelIDs
    }
}
