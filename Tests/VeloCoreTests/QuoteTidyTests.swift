import Testing
import Foundation
@testable import VeloCore

@Suite struct QuoteTidyTests {
    private func parent(text: String) -> Message {
        Message(id: "m", threadID: "t", sender: "Feross <feross@socket.dev>",
                recipients: [], subject: "s", date: Date(timeIntervalSince1970: 100),
                bodyHTML: nil, bodyText: text, isUnread: false, labelIDs: [])
    }

    // MARK: - Blank-line runs

    @Test func aRunOfBlankLinesBecomesOne() {
        // A marketing email's plain half is double-spaced throughout, so every
        // paragraph arrived with two or three empty quote markers under it.
        let quoted = QuotedReply.text(quoting: parent(text: "One\n\n\n\nTwo"))

        #expect(quoted.contains("> One\n>\n> Two"))
    }

    @Test func aSingleBlankLineIsLeftAlone() {
        // Paragraphs are still paragraphs; this is about runs, not spacing.
        let quoted = QuotedReply.text(quoting: parent(text: "One\n\nTwo"))

        #expect(quoted.contains("> One\n>\n> Two"))
    }

    @Test func blankLinesAtTheEndAreDropped() {
        let quoted = QuotedReply.text(quoting: parent(text: "One\n\n\n"))

        #expect(quoted.hasSuffix("> One"))
    }

    @Test func theTextItselfIsNotTouched() {
        // Quoting is not the place to edit what somebody wrote.
        let long = "Read (https://m.socket.dev/e3t/Ctc/5F+113/d2vCdQ04/MW5spFg3qpmW5mtsCN4KRQ)"
        let quoted = QuotedReply.text(quoting: parent(text: long))

        #expect(quoted.contains(long))
    }

    // MARK: - The preview

    @Test func thePreviewShortensTrackingURLs() {
        // Only for reading. What goes on the wire keeps the sender's words
        // exactly as they wrote them.
        let long = "Read (https://m.socket.dev/e3t/Ctc/5F+113/d2vCdQ04/MW5spFg3qpmW5mtsCN4KRQ1W4TqGZG5TbzFCN6G5Tqv3l5QzW5BW0B06lZ3pMW9gH5)"
        let preview = QuotedReply.preview(of: parent(text: long))

        #expect(preview.contains("https://m.socket.dev/\u{2026}"))
        #expect(!preview.contains("MW5spFg3qpmW5mtsCN4KRQ"))
    }

    @Test func aShortLinkIsLeftReadable() {
        let preview = QuotedReply.preview(of: parent(text: "See https://socket.dev/blog"))
        #expect(preview.contains("https://socket.dev/blog"))
    }

    @Test func thePreviewPrefersWhatTheReaderActuallySaw() {
        // An HTML message's plain half is a machine's idea of the message.
        // The rendered text is what the reader was looking at a moment ago.
        let message = Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                              subject: "s", date: Date(timeIntervalSince1970: 100),
                              bodyHTML: "<p>Supply chain attacks</p>",
                              bodyText: "Supply chain attacks (https://very/long/tracking/url/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)",
                              isUnread: false, labelIDs: [])

        #expect(QuotedReply.preview(of: message) == "Supply chain attacks")
    }

    @Test func thePreviewFallsBackToPlainTextWhenThereIsNoHTML() {
        #expect(QuotedReply.preview(of: parent(text: "Just words")) == "Just words")
    }
}
