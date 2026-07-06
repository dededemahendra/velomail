import Foundation
import GRDB

public struct Message: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: String
    public var threadID: String
    public var sender: String
    public var recipients: [String]
    public var subject: String
    public var date: Date
    public var bodyHTML: String?
    public var bodyText: String?
    public var isUnread: Bool
    public var labelIDs: [String]

    public static let databaseTableName = "message"

    public init(id: String, threadID: String, sender: String, recipients: [String],
                subject: String, date: Date, bodyHTML: String?, bodyText: String?,
                isUnread: Bool, labelIDs: [String]) {
        self.id = id
        self.threadID = threadID
        self.sender = sender
        self.recipients = recipients
        self.subject = subject
        self.date = date
        self.bodyHTML = bodyHTML
        self.bodyText = bodyText
        self.isUnread = isUnread
        self.labelIDs = labelIDs
    }
}
