import Foundation
import GRDB

public struct Message: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: String
    public var threadID: String
    public var sender: String
    public var recipients: [String]
    /// Carbon-copy addresses. Needed to build a reply-all.
    public var cc: [String]
    public var subject: String
    public var date: Date
    public var bodyHTML: String?
    public var bodyText: String?
    public var isUnread: Bool
    public var labelIDs: [String]
    /// The RFC 5322 `Message-ID` header. Distinct from `id`, which is Gmail's own
    /// identifier; only this value is meaningful to other mail systems, so it is
    /// what a reply must cite in `In-Reply-To`/`References`.
    public var messageIDHeader: String?
    public var inReplyTo: String?
    /// The `References` header, split into individual message ids, oldest first.
    public var references: [String]
    /// RFC 2369 `List-Unsubscribe`, raw. Its presence is also the sender's own
    /// admission that this is a bulk mailing, which is newsletter detection
    /// without a classifier.
    public var listUnsubscribe: String?

    public static let databaseTableName = "message"

    public init(id: String, threadID: String, sender: String, recipients: [String],
                cc: [String] = [], subject: String, date: Date,
                bodyHTML: String?, bodyText: String?,
                isUnread: Bool, labelIDs: [String],
                messageIDHeader: String? = nil, inReplyTo: String? = nil,
                references: [String] = [], listUnsubscribe: String? = nil) {
        self.id = id
        self.threadID = threadID
        self.sender = sender
        self.recipients = recipients
        self.cc = cc
        self.subject = subject
        self.date = date
        self.bodyHTML = bodyHTML
        self.bodyText = bodyText
        self.isUnread = isUnread
        self.labelIDs = labelIDs
        self.messageIDHeader = messageIDHeader
        self.inReplyTo = inReplyTo
        self.references = references
        self.listUnsubscribe = listUnsubscribe
    }
}
