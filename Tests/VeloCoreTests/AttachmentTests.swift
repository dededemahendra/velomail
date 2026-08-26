import Testing
import Foundation
@testable import VeloCore

private func decodeDTO(_ json: String) throws -> GmailMessageDTO {
    try JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
}

/// A message with a plain-text body, a referenced PDF and an inline logo.
private let mixedJSON = """
{
  "id": "m1", "threadId": "t1", "labelIds": ["INBOX"], "internalDate": "1000",
  "payload": {
    "mimeType": "multipart/mixed",
    "headers": [{"name": "Subject", "value": "Invoice"}],
    "parts": [
      {"mimeType": "text/plain", "body": {"data": "aGVsbG8"}},
      {"mimeType": "application/pdf", "filename": "invoice.pdf",
       "body": {"attachmentId": "att-1", "size": 84213}},
      {"mimeType": "image/png", "filename": "logo.png",
       "body": {"data": "aW1hZ2U", "size": 5}}
    ]
  }
}
"""

@Suite struct AttachmentMappingTests {
    @Test func extractsAReferencedAttachment() throws {
        let attachments = GmailMessageMapper.attachments(from: try decodeDTO(mixedJSON))
        let pdf = try #require(attachments.first { $0.filename == "invoice.pdf" })
        #expect(pdf.mimeType == "application/pdf")
        #expect(pdf.size == 84_213)
        #expect(pdf.attachmentID == "att-1")
        #expect(pdf.inlineData == nil)
    }

    @Test func keepsInlineDataSoItNeedsNoFetch() throws {
        let attachments = GmailMessageMapper.attachments(from: try decodeDTO(mixedJSON))
        let logo = try #require(attachments.first { $0.filename == "logo.png" })
        #expect(logo.attachmentID == nil)
        #expect(logo.inlineData == "aW1hZ2U")
    }

    @Test func bodyPartsWithoutAFilenameAreNotAttachments() throws {
        let attachments = GmailMessageMapper.attachments(from: try decodeDTO(mixedJSON))
        // The text/plain body must not show up as a file.
        #expect(attachments.count == 2)
    }

    @Test func attachmentsAreFoundInNestedMultiparts() throws {
        let dto = try decodeDTO("""
        {"id":"m","threadId":"t","internalDate":"1",
         "payload":{"mimeType":"multipart/mixed","parts":[
           {"mimeType":"multipart/alternative","parts":[
             {"mimeType":"text/plain","body":{"data":"aGk"}},
             {"mimeType":"text/html","body":{"data":"aGk"}}]},
           {"mimeType":"application/zip","filename":"deep.zip",
            "body":{"attachmentId":"att-deep","size":10}}]}}
        """)
        #expect(GmailMessageMapper.attachments(from: dto).map(\.filename) == ["deep.zip"])
    }

    @Test func aMessageWithNoAttachmentsYieldsNone() throws {
        let dto = try decodeDTO("""
        {"id":"m","threadId":"t","internalDate":"1",
         "payload":{"mimeType":"text/plain","body":{"data":"aGk"}}}
        """)
        #expect(GmailMessageMapper.attachments(from: dto).isEmpty)
    }

    @Test func attachmentsCarryTheirMessageAndThread() throws {
        let attachments = GmailMessageMapper.attachments(from: try decodeDTO(mixedJSON))
        #expect(attachments.allSatisfy { $0.messageID == "m1" })
    }

    @Test func aMissingSizeIsZeroRatherThanAFailure() throws {
        let dto = try decodeDTO("""
        {"id":"m","threadId":"t","internalDate":"1",
         "payload":{"mimeType":"multipart/mixed","parts":[
           {"mimeType":"application/octet-stream","filename":"unknown.bin",
            "body":{"attachmentId":"a"}}]}}
        """)
        #expect(GmailMessageMapper.attachments(from: dto).first?.size == 0)
    }
}

@Suite struct AttachmentStorageTests {
    private func makeStore() throws -> MailStore {
        let store = MailStore(try AppDatabase.makeInMemory())
        try store.upsert(MailThread(id: "t1", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: true, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m1", threadID: "t1", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: false, labelIDs: ["INBOX"]))
        return store
    }

    private func attachment(_ id: String, name: String = "invoice.pdf") -> MailAttachment {
        MailAttachment(id: id, messageID: "m1", filename: name, mimeType: "application/pdf",
                   size: 100, attachmentID: "att-\(id)", inlineData: nil)
    }

    @Test func attachmentTableExists() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let exists = try db.tableExists("attachment")
            #expect(exists)
        }
    }

    @Test func attachmentsRoundTrip() throws {
        let store = try makeStore()
        try store.upsert(attachment("a1"))
        #expect(try store.attachments(forMessage: "m1") == [attachment("a1")])
    }

    @Test func upsertingTheSameAttachmentDoesNotDuplicate() throws {
        let store = try makeStore()
        try store.upsert(attachment("a1"))
        try store.upsert(attachment("a1"))
        // Sync re-hydrates messages constantly.
        #expect(try store.attachments(forMessage: "m1").count == 1)
    }

    @Test func deletingAMessageRemovesItsAttachments() throws {
        let store = try makeStore()
        try store.upsert(attachment("a1"))

        try store.deleteMessage(id: "m1")

        #expect(try store.attachments(forMessage: "m1").isEmpty)
    }

    @Test func attachmentsComeBackInAStableOrder() throws {
        let store = try makeStore()
        try store.upsert(attachment("a2", name: "b.pdf"))
        try store.upsert(attachment("a1", name: "a.pdf"))
        #expect(try store.attachments(forMessage: "m1").map(\.filename) == ["a.pdf", "b.pdf"])
    }
}

@Suite struct AttachmentReconcileTests {
    @Test func reconcilingAMessageStoresItsAttachments() throws {
        let store = MailStore(try AppDatabase.makeInMemory())

        try InboxReconciler.reconcile([try decodeDTO(mixedJSON)], into: store)

        // Without this, sync knows a message has files and stores none of them.
        #expect(try store.attachments(forMessage: "m1").map(\.filename)
                == ["invoice.pdf", "logo.png"])
    }

    @Test func reconcilingTwiceDoesNotDuplicateAttachments() throws {
        let store = MailStore(try AppDatabase.makeInMemory())
        let dto = try decodeDTO(mixedJSON)

        try InboxReconciler.reconcile([dto], into: store)
        try InboxReconciler.reconcile([dto], into: store)

        #expect(try store.attachments(forMessage: "m1").count == 2)
    }
}
