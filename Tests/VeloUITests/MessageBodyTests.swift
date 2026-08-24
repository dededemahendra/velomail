import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct MessageBodyTests {
    private func message(html: String?, text: String?) -> Message {
        Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                subject: "s", date: Date(timeIntervalSince1970: 0),
                bodyHTML: html, bodyText: text, isUnread: false, labelIDs: [])
    }

    @Test func documentEmbedsTheHTMLBody() {
        let document = MessageBodyView.document(for: message(html: "<p>hello</p>", text: nil))
        #expect(document.contains("<p>hello</p>"))
    }

    @Test func plainTextBodiesAreEscapedNotInjected() {
        let document = MessageBodyView.document(for: message(html: nil, text: "<script>x</script>"))
        #expect(document.contains("&lt;script&gt;"))
        #expect(!document.contains("<script>x"))
    }

    @Test func strippingRemovesElementsThatFetchRemotely() {
        let stripped = MessageBodyView.stripRemoteContent(
            from: #"<p>hi</p><img src="https://tracker.example/p.gif"><iframe src="https://x"></iframe>"#)
        #expect(!stripped.contains("img"))
        #expect(!stripped.contains("iframe"))
        #expect(stripped.contains("<p>hi</p>"))
    }

    @Test func strippingKeepsOrdinaryMarkup() {
        let stripped = MessageBodyView.stripRemoteContent(from: "<p>keep</p><blockquote>me</blockquote>")
        #expect(stripped.contains("<p>keep</p>"))
        #expect(stripped.contains("<blockquote>me</blockquote>"))
    }
}
