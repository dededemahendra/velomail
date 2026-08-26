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

    // MARK: - Images that carry their own bytes

    @Test func aDataURIImageSurvivesBlocking() {
        // The point of blocking remote content is that it stops the sender
        // learning the message was opened. A data: URI makes no request at all,
        // so removing it costs the reader a picture and protects nothing.
        let html = #"<p>hi</p><img src="data:image/png;base64,AAA">"#
        #expect(MessageBodyView.stripRemoteContent(from: html).contains("data:image/png"))
    }

    @Test func aRemoteImageIsStillStripped() {
        let html = #"<img src="https://tracker.example/pixel.gif">"#
        #expect(!MessageBodyView.stripRemoteContent(from: html).contains("img"))
    }

    @Test func aDataURIScriptIsStillStripped() {
        // Never for scripts, whatever the scheme.
        let html = #"<script src="data:text/javascript,alert(1)"></script>"#
        #expect(!MessageBodyView.stripRemoteContent(from: html).contains("script"))
    }

    @Test func aMixedBodyKeepsOnlyTheLocalImage() {
        let html = #"<img src="data:image/png;base64,AAA"><img src="https://x/y.gif">"#
        let out = MessageBodyView.stripRemoteContent(from: html)
        #expect(out.contains("data:image/png"))
        #expect(!out.contains("https://x/y.gif"))
    }
}
