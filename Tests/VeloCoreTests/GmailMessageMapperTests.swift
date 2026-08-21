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

    // MARK: - Per-message labels (C2)

    private func msg(_ id: String, labels: [String]) -> Message {
        Message(id: id, threadID: "t", sender: "", recipients: [], subject: "",
                date: Date(timeIntervalSince1970: 0), bodyHTML: nil, bodyText: nil,
                isUnread: false, labelIDs: labels)
    }

    @Test func messageCopiesLabelIDsFromDTO() throws {
        let dto = try decodeDTO(htmlMessageJSON)   // labelIds: ["INBOX","UNREAD"]
        let message = GmailMessageMapper.message(from: dto)
        #expect(message.labelIDs == ["INBOX", "UNREAD"])
    }

    @Test func messageLabelIDsEmptyWhenDTOHasNone() throws {
        let dto = try decodeDTO(#"{"id":"x","threadId":"t","internalDate":"1"}"#)
        let message = GmailMessageMapper.message(from: dto)
        #expect(message.labelIDs == [])
    }

    @Test func threadAggregateUnionsLabelsSorted() {
        let (labels, _) = GmailMessageMapper.threadAggregate(
            from: [msg("a", labels: ["INBOX", "B"]), msg("b", labels: ["A", "INBOX"])])
        #expect(labels == ["A", "B", "INBOX"])
    }

    @Test func threadAggregateIsUnreadIffAnyMessageUnread() {
        let (_, unread) = GmailMessageMapper.threadAggregate(
            from: [msg("a", labels: ["INBOX"]), msg("b", labels: ["INBOX", "UNREAD"])])
        #expect(unread == true)
        let (_, allRead) = GmailMessageMapper.threadAggregate(from: [msg("a", labels: ["INBOX"])])
        #expect(allRead == false)
    }

    @Test func threadAggregateEmptyIsNoneAndFalse() {
        let (labels, unread) = GmailMessageMapper.threadAggregate(from: [])
        #expect(labels == [])
        #expect(unread == false)
    }

    @Test func mapperPopulatesReplyThreadingHeaders() throws {
        let dto = try decodeDTO("""
        {
          "id": "m9", "threadId": "t9", "internalDate": "1719900000000",
          "payload": { "mimeType": "text/plain", "headers": [
            {"name": "From", "value": "alice@example.com"},
            {"name": "Cc", "value": "dave@example.com, erin@example.com"},
            {"name": "Message-ID", "value": "<abc@mail.example.com>"},
            {"name": "In-Reply-To", "value": "<parent@mail.example.com>"},
            {"name": "References", "value": "<root@mail.example.com>"}
          ] }
        }
        """)
        let message = GmailMessageMapper.message(from: dto)
        #expect(message.cc == ["dave@example.com", "erin@example.com"])
        #expect(message.messageIDHeader == "<abc@mail.example.com>")
        #expect(message.inReplyTo == "<parent@mail.example.com>")
        #expect(message.references == ["<root@mail.example.com>"])
    }

    @Test func mapperParsesMultipleReferencesSeparatedByWhitespace() throws {
        let dto = try decodeDTO("""
        {
          "id": "m10", "threadId": "t9", "internalDate": "1719900000000",
          "payload": { "mimeType": "text/plain", "headers": [
            {"name": "References", "value": "<a@x.com>\\n <b@x.com>\\t<c@x.com>"}
          ] }
        }
        """)
        #expect(GmailMessageMapper.message(from: dto).references
                == ["<a@x.com>", "<b@x.com>", "<c@x.com>"])
    }

    @Test func mapperLeavesReplyHeadersEmptyWhenAbsent() throws {
        let dto = try decodeDTO("""
        {
          "id": "m11", "threadId": "t9", "internalDate": "1719900000000",
          "payload": { "mimeType": "text/plain", "headers": [
            {"name": "From", "value": "alice@example.com"}
          ] }
        }
        """)
        let message = GmailMessageMapper.message(from: dto)
        #expect(message.cc == [])
        #expect(message.messageIDHeader == nil)
        #expect(message.inReplyTo == nil)
        #expect(message.references == [])
    }

    @Test func threadTakesItsSenderFromTheNewestMessage() throws {
        let older = try decodeDTO("""
        {"id":"m1","threadId":"t","internalDate":"1000","labelIds":["INBOX"],
         "payload":{"mimeType":"text/plain","headers":[{"name":"From","value":"old@x.com"}]}}
        """)
        let newer = try decodeDTO("""
        {"id":"m2","threadId":"t","internalDate":"2000","labelIds":["INBOX"],
         "payload":{"mimeType":"text/plain","headers":[{"name":"From","value":"Newest <new@x.com>"}]}}
        """)

        // A list row shows who spoke last, not who started the thread.
        #expect(GmailMessageMapper.thread(from: [older, newer])?.sender == "Newest <new@x.com>")
    }
}
