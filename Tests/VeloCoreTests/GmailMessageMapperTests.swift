import Testing
import Foundation
@testable import VeloCore

private func decodeDTO(_ json: String) throws -> GmailMessageDTO {
    try JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
}

// A multipart/alternative message with plain + HTML parts, two recipients, UNREAD.
// Body data is base64url ("PGI-...L2I-" contains the URL-safe '-') to exercise decoding.
private let htmlMessageJSON = """
{
  "id": "m1",
  "threadId": "t1",
  "labelIds": ["INBOX", "UNREAD"],
  "snippet": "hello snippet",
  "internalDate": "1719900000000",
  "payload": {
    "mimeType": "multipart/alternative",
    "headers": [
      {"name": "From", "value": "Alice <alice@example.com>"},
      {"name": "To", "value": "bob@example.com, carol@example.com"},
      {"name": "Subject", "value": "Meeting"}
    ],
    "parts": [
      {"mimeType": "text/plain", "body": {"data": "cGxhaW4gYm9keQ"}},
      {"mimeType": "text/html", "body": {"data": "PGI-aGVsbG88L2I-"}}
    ]
  }
}
"""

// A single-part text/plain message, no To header, read (no UNREAD label).
private let plainMessageJSON = """
{
  "id": "m2",
  "threadId": "t2",
  "labelIds": ["INBOX"],
  "snippet": "plain snippet",
  "internalDate": "1719800000000",
  "payload": {
    "mimeType": "text/plain",
    "headers": [
      {"name": "From", "value": "carol@example.com"},
      {"name": "Subject", "value": "Hi"}
    ],
    "body": {"data": "cGxhaW4gYm9keQ"}
  }
}
"""

// Older message in thread t3, no attachment.
private let threadOlderJSON = """
{
  "id": "a",
  "threadId": "t3",
  "labelIds": ["INBOX"],
  "snippet": "older",
  "internalDate": "1000000000000",
  "payload": { "mimeType": "text/plain", "body": {"data": "cGxhaW4gYm9keQ"} }
}
"""

// Newer message in thread t3, UNREAD, with a named attachment part.
private let threadNewerJSON = """
{
  "id": "b",
  "threadId": "t3",
  "labelIds": ["INBOX", "UNREAD"],
  "snippet": "newer",
  "internalDate": "2000000000000",
  "payload": {
    "mimeType": "multipart/mixed",
    "parts": [
      {"mimeType": "text/plain", "body": {"data": "cGxhaW4gYm9keQ"}},
      {"mimeType": "image/png", "filename": "photo.png", "body": {"attachmentId": "abc"}}
    ]
  }
}
"""

@Suite struct GmailMessageMapperTests {
    @Test func mapsFullHtmlMessageFields() throws {
        let dto = try decodeDTO(htmlMessageJSON)
        let message = GmailMessageMapper.message(from: dto)

        #expect(message.id == "m1")
        #expect(message.threadID == "t1")
        #expect(message.sender == "Alice <alice@example.com>")
        #expect(message.recipients == ["bob@example.com", "carol@example.com"])
        #expect(message.subject == "Meeting")
        #expect(message.date == Date(timeIntervalSince1970: 1_719_900_000))
        #expect(message.bodyText == "plain body")
        #expect(message.bodyHTML == "<b>hello</b>")   // base64url-decoded
        #expect(message.isUnread == true)
    }

    @Test func mapsPlainTextOnlyMessage() throws {
        let dto = try decodeDTO(plainMessageJSON)
        let message = GmailMessageMapper.message(from: dto)

        #expect(message.recipients == [])
        #expect(message.subject == "Hi")
        #expect(message.bodyText == "plain body")
        #expect(message.bodyHTML == nil)
        #expect(message.isUnread == false)
    }

    @Test func derivesThreadFromMultipleMessages() throws {
        let older = try decodeDTO(threadOlderJSON)
        let newer = try decodeDTO(threadNewerJSON)

        let thread = try #require(GmailMessageMapper.thread(from: [older, newer]))

        #expect(thread.id == "t3")
        #expect(thread.snippet == "newer")   // from newest message
        #expect(thread.lastMessageDate == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(thread.isUnread == true)
        #expect(thread.hasAttachments == true)
        #expect(thread.labelIDs == ["INBOX", "UNREAD"])   // union, sorted
    }

    @Test func threadFromEmptyIsNil() {
        #expect(GmailMessageMapper.thread(from: []) == nil)
    }
}
