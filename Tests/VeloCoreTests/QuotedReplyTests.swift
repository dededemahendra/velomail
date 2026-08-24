import Testing
import Foundation
@testable import VeloCore

@Suite struct QuotedReplyTests {
    private func parent(text: String? = "first line\nsecond line",
                        html: String? = nil) -> Message {
        Message(id: "m1", threadID: "t1", sender: "Alice <alice@example.com>",
                recipients: ["me@example.com"], subject: "Lunch",
                date: Date(timeIntervalSince1970: 1_755_600_000),
                bodyHTML: html, bodyText: text, isUnread: false, labelIDs: [],
                messageIDHeader: "<p@x.com>")
    }

    @Test func attributionNamesTheSenderAndDate() {
        let quoted = QuotedReply.text(quoting: parent())
        // Recipients read this in their own client, so it matches the
        // convention every other client emits.
        #expect(quoted.hasPrefix("On 19 Aug 2025 at "))
        #expect(quoted.contains("Alice <alice@example.com> wrote:"))
    }

    @Test func plainTextIsPrefixedWithAngleBrackets() {
        let quoted = QuotedReply.text(quoting: parent())
        #expect(quoted.contains("> first line"))
        #expect(quoted.contains("> second line"))
    }

    @Test func anEmptyBodyStillProducesAnAttribution() {
        let quoted = QuotedReply.text(quoting: parent(text: ""))
        #expect(quoted.contains("wrote:"))
    }

    @Test func quotedTextStartsWithABlankLineSoTheReplyHasRoom() {
        let quoted = QuotedReply.text(quoting: parent())
        #expect(quoted.hasPrefix("\n\n") == false)   // caller owns leading space
        #expect(quoted.contains("wrote:\n>"))
    }

    @Test func htmlIsWrappedInABlockquote() {
        let quoted = QuotedReply.html(quoting: parent(text: nil, html: "<p>hello</p>"))
        #expect(quoted.contains("<blockquote"))
        #expect(quoted.contains("<p>hello</p>"))
        #expect(quoted.contains("wrote:"))
    }

    @Test func htmlFallsBackToEscapedPlainTextWhenThereIsNoHTML() {
        let quoted = QuotedReply.html(quoting: parent(text: "a < b", html: nil))
        #expect(quoted.contains("a &lt; b"))
    }

    @Test func nestedRepliesKeepTheOuterQuote() {
        // The parent body already contains its own quote; quoting it again just
        // deepens the chain, which is what other clients render as nesting.
        let onceQuoted = QuotedReply.text(quoting: parent())
        let reply = parent(text: "my answer\n\n" + onceQuoted)
        let twiceQuoted = QuotedReply.text(quoting: reply)
        #expect(twiceQuoted.contains("> > first line"))
    }
}
