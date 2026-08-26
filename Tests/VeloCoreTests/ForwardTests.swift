import Testing
import Foundation
@testable import VeloCore

private func original(subject: String = "Invoice for August",
                      attachments: [DraftAttachment] = []) -> Message {
    Message(id: "m1", threadID: "t1", sender: "Alice <alice@example.com>",
            recipients: ["me@example.com"], cc: ["bob@example.com"],
            subject: subject, date: Date(timeIntervalSince1970: 1_755_600_000),
            bodyHTML: nil, bodyText: "Attached is the invoice.", isUnread: false,
            labelIDs: ["INBOX"], messageIDHeader: "<orig@x.com>",
            inReplyTo: nil, references: [])
}

@Suite struct ForwardTests {
    private let me = "me@example.com"

    @Test func aForwardStartsWithNoRecipient() {
        // You are sending it to someone new; guessing would be worse than blank.
        #expect(Draft.forward(original(), from: me).to.isEmpty)
    }

    @Test func theSubjectIsPrefixed() {
        #expect(Draft.forward(original(), from: me).subject == "Fwd: Invoice for August")
    }

    @Test func anAlreadyForwardedSubjectIsNotPrefixedTwice() {
        #expect(Draft.forward(original(subject: "Fwd: Invoice"), from: me).subject == "Fwd: Invoice")
        #expect(Draft.forward(original(subject: "FWD: Invoice"), from: me).subject == "FWD: Invoice")
    }

    @Test func aForwardIsNotPartOfTheOriginalThread() {
        let draft = Draft.forward(original(), from: me)

        // The single most important property here. Threading a forward would
        // deliver it to everyone on the original conversation -- the people you
        // were deliberately forwarding *away* from.
        #expect(draft.threadID == nil)
        #expect(draft.inReplyTo == nil)
        #expect(draft.references.isEmpty)
    }

    @Test func theOriginalIsQuotedWithItsHeaders() {
        let body = Draft.forward(original(), from: me).bodyText

        #expect(body.contains("Forwarded message"))
        #expect(body.contains("Alice <alice@example.com>"))
        #expect(body.contains("Invoice for August"))
        #expect(body.contains("Attached is the invoice."))
    }

    @Test func theOriginalRecipientsAreShownInTheQuote() {
        // Context the reader needs: who else already had this.
        let body = Draft.forward(original(), from: me).bodyText
        #expect(body.contains("me@example.com"))
    }

    @Test func attachmentsAreCarriedAlong() {
        let file = DraftAttachment(filename: "invoice.pdf", mimeType: "application/pdf",
                                   data: Data("PDF".utf8))

        let draft = Draft.forward(original(), from: me, attachments: [file])

        // Forwarding an invoice without the invoice is useless.
        #expect(draft.attachments == [file])
    }

    @Test func aForwardWithoutAttachmentsCarriesNone() {
        #expect(Draft.forward(original(), from: me).attachments.isEmpty)
    }

    @Test func roomIsLeftToWriteAboveTheQuote() {
        #expect(Draft.forward(original(), from: me).bodyText.hasPrefix("\n\n"))
    }

    @Test func anHTMLOriginalProducesAnHTMLForward() {
        var rich = original()
        rich.bodyHTML = "<p>Attached is the invoice.</p>"
        let draft = Draft.forward(rich, from: me)

        #expect(draft.bodyHTML?.contains("<p>Attached is the invoice.</p>") == true)
        #expect(draft.bodyHTML?.contains("Forwarded message") == true)
    }
}
