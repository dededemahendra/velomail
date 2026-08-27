import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct EmptyBodyTests {
    private func message(text: String? = nil, html: String? = nil) -> Message {
        Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [], subject: "s",
                date: Date(), bodyHTML: html, bodyText: text, isUnread: false, labelIDs: [])
    }

    @Test func aMessageWithNothingInItSaysSo() {
        // A bare attachment, a calendar invitation, a bounce: rendered as an
        // empty white pane it reads as a bug in this app.
        let html = MessageBodyView.document(for: message())
        #expect(html.contains("This message has no text."))
    }

    @Test func whitespaceIsNothing() {
        #expect(MessageBodyView.document(for: message(text: "  \n\t ")).contains("no text"))
    }

    @Test func anEmptyHTMLBodyFallsThroughRatherThanRenderingBlank() {
        // Gmail returns an empty string rather than nothing at all for some
        // messages, and that took the HTML path straight to a blank pane.
        #expect(MessageBodyView.document(for: message(text: "Real words", html: ""))
            .contains("Real words"))
    }

    @Test func realTextIsUntouched() {
        let html = MessageBodyView.document(for: message(text: "The planting moved."))
        #expect(html.contains("The planting moved."))
        #expect(!html.contains("no text"))
    }

    @Test func realHTMLIsStillPaintedAsTheSenderWroteIt() {
        let html = MessageBodyView.document(for: message(html: "<b>Hello</b>"))
        #expect(html.contains("<b>Hello</b>"))
        #expect(!html.contains("no text"))
    }
}
