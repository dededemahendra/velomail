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

    // MARK: - The surface a message is painted on

    private func htmlMessage(_ body: String) -> Message {
        Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [], subject: "s",
                date: Date(timeIntervalSince1970: 1), bodyHTML: body, bodyText: nil,
                isUnread: false, labelIDs: [])
    }

    private func plainMessage(_ body: String) -> Message {
        Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [], subject: "s",
                date: Date(timeIntervalSince1970: 1), bodyHTML: nil, bodyText: body,
                isUnread: false, labelIDs: [])
    }

    @Test func htmlMailIsPaintedOnItsOwnLightSurface() {
        // Newsletters are authored for a white page and paint their own white
        // behind the content only. On a transparent backdrop in a dark window
        // that leaves a white island floating in black, which reads as broken
        // rendering rather than as a design.
        let out = MessageBodyView.document(for: htmlMessage("<p>hi</p>"))
        #expect(out.contains("background: #ffffff"))
        #expect(!out.contains("background: transparent"))
    }

    @Test func theSurfaceFillsThePaneNotJustTheText() {
        // A short message must not leave the rest of the pane a different colour.
        let out = MessageBodyView.document(for: htmlMessage("<p>hi</p>"))
        #expect(out.contains("min-height: 100%"))
    }

    @Test func htmlMailKeepsDarkTextRatherThanInvertingWithTheSystem() {
        // The sender chose colours for a light page; letting the system flip
        // only our half produces dark-on-dark in half the message.
        let out = MessageBodyView.document(for: htmlMessage("<p>hi</p>"))
        #expect(out.contains("color-scheme: light"))
        #expect(!out.contains("color-scheme: light dark"))
    }

    @Test func plainTextStillFollowsTheSystem() {
        // We author that one, so it can and should match the app around it.
        let out = MessageBodyView.document(for: plainMessage("hello"))
        #expect(out.contains("color-scheme: light dark"))
        #expect(out.contains("prefers-color-scheme: dark"))
    }

    // MARK: - Telling the reader why the pictures are missing

    @Test func aMessageWithRemoteImagesIsRecognised() {
        #expect(MessageBodyView.hasRemoteImages(htmlMessage(#"<img src="https://x/y.gif">"#)))
        #expect(MessageBodyView.hasRemoteImages(htmlMessage("<img src='http://x/y.gif'>")))
    }

    @Test func aMessageWithOnlyItsOwnImagesIsNot() {
        // Nothing was blocked, so there is nothing to explain.
        #expect(!MessageBodyView.hasRemoteImages(htmlMessage(#"<img src="data:image/png;base64,AAA">"#)))
        #expect(!MessageBodyView.hasRemoteImages(plainMessage("no pictures here")))
    }

    @Test func aCidReferenceIsNotRemote() {
        #expect(!MessageBodyView.hasRemoteImages(htmlMessage(#"<img src="cid:logo@x">"#)))
    }

    // MARK: - Blocked pictures leave no wreckage

    @Test func aBlockedImageIsNotDrawnAtAll() {
        // A blocked <img> still lays out: an empty bordered box the reader
        // reads as a broken message rather than as a choice we made for them.
        let out = MessageBodyView.document(for: htmlMessage(#"<img src="https://x/y.gif">"#))
        #expect(out.contains(#"img[src^="http"]"#))
        #expect(out.contains("display: none"))
    }

    @Test func loadingThemPutsThemBack() {
        let out = MessageBodyView.document(for: htmlMessage(#"<img src="https://x/y.gif">"#),
                                           allowingRemote: true)
        #expect(!out.contains("display: none"))
    }

    @Test func aMessagesOwnPicturesAreNeverHidden() {
        // They carry their own bytes and fetch nothing, so there is no reason
        // to hide them and every reason not to.
        let out = MessageBodyView.document(for: htmlMessage(#"<img src="data:image/png;base64,AAA">"#))
        #expect(out.contains(#"img[src^="http"]"#))   // the rule is scoped to remote ones
    }
}
