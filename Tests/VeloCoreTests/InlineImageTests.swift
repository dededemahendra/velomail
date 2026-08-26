import Testing
import Foundation
@testable import VeloCore

@Suite struct InlineImageTests {
    private func dto(contentID: String?, data: String, attachmentId: String? = nil) -> GmailMessageDTO {
        let idHeader = contentID.map {
            #"{"name":"Content-ID","value":"\#($0)"},"#
        } ?? ""
        let body = attachmentId.map { #""attachmentId":"\#($0)","# } ?? ""
        let json = """
        {"id":"m","threadId":"t","labelIds":["INBOX"],"snippet":"s","internalDate":"1000",
         "payload":{"mimeType":"multipart/related",
           "headers":[{"name":"From","value":"a@b.com"},{"name":"Subject","value":"s"}],
           "parts":[
             {"mimeType":"text/html","body":{"data":"PHA-aGk8L3A-"}},
             {"mimeType":"image/png","filename":"logo.png",
              "headers":[\(idHeader){"name":"Content-Type","value":"image/png"}],
              "body":{\(body)"size":9,"data":"\(data)"}}
           ]}}
        """
        return try! JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
    }

    // MARK: - Keeping the id

    @Test func anInlinePartRemembersItsContentID() throws {
        let found = GmailMessageMapper.attachments(from: dto(contentID: "<logo@velo>", data: "AAA"))
        #expect(found.first?.contentID == "logo@velo")
    }

    @Test func theAnglesAreStripped() throws {
        // Bodies reference cid:logo@velo, never cid:<logo@velo>.
        let found = GmailMessageMapper.attachments(from: dto(contentID: "<logo@velo>", data: "AAA"))
        #expect(found.first?.contentID?.hasPrefix("<") == false)
    }

    @Test func anOrdinaryAttachmentHasNoContentID() throws {
        let found = GmailMessageMapper.attachments(from: dto(contentID: nil, data: "AAA"))
        #expect(found.first?.contentID == nil)
    }

    // MARK: - Putting it in the body

    @Test func aCidReferenceBecomesTheImage() throws {
        let attachment = MailAttachment(id: "a", messageID: "m", filename: "logo.png",
                                        mimeType: "image/png", size: 3, attachmentID: nil,
                                        inlineData: "iVBORw", contentID: "logo@velo")
        let html = InlineImages.embed(#"<img src="cid:logo@velo">"#, using: [attachment])

        #expect(html.contains("data:image/png;base64,"))
        #expect(!html.contains("cid:"))
    }

    @Test func base64urlIsTranslatedForTheDataURI() throws {
        // Gmail returns base64url; a data: URI needs standard base64, and the
        // difference is exactly the characters that appear in binary data.
        let attachment = MailAttachment(id: "a", messageID: "m", filename: "logo.png",
                                        mimeType: "image/png", size: 3, attachmentID: nil,
                                        inlineData: "a-b_c", contentID: "logo@velo")
        let html = InlineImages.embed(#"<img src="cid:logo@velo">"#, using: [attachment])

        #expect(html.contains("a+b/c"))
        #expect(!html.contains("a-b_c"))
    }

    @Test func singleQuotesAreHandledToo() throws {
        let attachment = MailAttachment(id: "a", messageID: "m", filename: "l.png",
                                        mimeType: "image/png", size: 3, attachmentID: nil,
                                        inlineData: "AAA", contentID: "x@y")
        #expect(InlineImages.embed("<img src='cid:x@y'>", using: [attachment])
            .contains("data:image/png;base64,AAA"))
    }

    @Test func anUnmatchedReferenceIsLeftAlone() throws {
        // Better a broken image than a wrong one: substituting the nearest
        // attachment would show the reader a picture the sender did not send.
        let html = InlineImages.embed(#"<img src="cid:missing@x">"#, using: [])
        #expect(html.contains("cid:missing@x"))
    }

    @Test func anAttachmentWithNoBytesYetIsSkipped() throws {
        // A large inline part is fetched on demand; until then there is nothing
        // to embed, and an empty data: URI renders as a broken image anyway.
        let attachment = MailAttachment(id: "a", messageID: "m", filename: "big.png",
                                        mimeType: "image/png", size: 900_000,
                                        attachmentID: "att1", inlineData: nil, contentID: "big@x")
        let html = InlineImages.embed(#"<img src="cid:big@x">"#, using: [attachment])
        #expect(html.contains("cid:big@x"))
    }

    @Test func aBodyWithNoImagesIsUntouched() throws {
        let html = "<p>plain</p>"
        #expect(InlineImages.embed(html, using: []) == html)
    }
}
