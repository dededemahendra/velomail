import Foundation
import GRDB

/// A file on a message.
///
/// Metadata only — the bytes are fetched when the user asks for them. Pulling
/// content during sync would mean a 500-message backfill dragging hundreds of
/// megabytes before the inbox is usable, and SQLite carrying it forever, for
/// files that are mostly never opened.
///
/// Named `MailAttachment` rather than `Attachment` because Swift Testing
/// already owns that name.
public struct MailAttachment: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    /// Stable per message+part, so re-hydrating a message updates rather than duplicates.
    public var id: String
    public var messageID: String
    public var filename: String
    public var mimeType: String
    public var size: Int
    /// Gmail's handle for fetching the content. Nil for an inline part.
    public var attachmentID: String?
    /// Base64url content, present only for small inline parts, which therefore
    /// need no fetch at all.
    public var inlineData: String?

    public static let databaseTableName = "attachment"

    public init(id: String, messageID: String, filename: String, mimeType: String,
                size: Int, attachmentID: String?, inlineData: String?) {
        self.id = id
        self.messageID = messageID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.attachmentID = attachmentID
        self.inlineData = inlineData
    }

    /// True when the content is already here.
    public var isInline: Bool { inlineData != nil }
}
