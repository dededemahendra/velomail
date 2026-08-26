import Testing
import Foundation
@testable import VeloCore

@Suite struct MarkdownBodyTests {
    private func html(_ markdown: String) -> String? { MarkdownBody.html(from: markdown) }

    // MARK: - When it does nothing

    @Test func plainProseProducesNoHTML() {
        // Nothing to format means nothing to send as HTML, so a plain message
        // stays a plain message on the wire.
        #expect(html("Just a normal sentence.") == nil)
        #expect(html("") == nil)
    }

    @Test func anEmailAddressIsNotEmphasis() {
        // a_b_c@x.com would become italics under a naive underscore rule.
        #expect(html("write to a_b_c@x.com") == nil)
    }

    // MARK: - Inline

    @Test func boldAndItalic() {
        #expect(html("**really** important")?.contains("<strong>really</strong>") == true)
        #expect(html("*maybe* important")?.contains("<em>maybe</em>") == true)
    }

    @Test func inlineCode() {
        #expect(html("run `swift test` first")?.contains("<code>swift test</code>") == true)
    }

    @Test func links() {
        let out = html("see [the map](https://example.com/map)")
        #expect(out?.contains(#"<a href="https://example.com/map">the map</a>"#) == true)
    }

    @Test func aBareURLBecomesALink() {
        #expect(html("see https://example.com/map now")?
            .contains(#"<a href="https://example.com/map">https://example.com/map</a>"#) == true)
    }

    // MARK: - Blocks

    @Test func bulletsBecomeAList() {
        let out = html("- one\n- two")
        #expect(out?.contains("<ul>") == true)
        #expect(out?.contains("<li>one</li>") == true)
        #expect(out?.contains("<li>two</li>") == true)
    }

    @Test func numbersBecomeAnOrderedList() {
        let out = html("1. first\n2. second")
        #expect(out?.contains("<ol>") == true)
        #expect(out?.contains("<li>first</li>") == true)
    }

    @Test func aQuotationAloneIsNotFormatting() {
        // Every reply carries the parent behind "> " lines. If that alone made
        // a message rich, no reply would ever be plain text again.
        #expect(html("> they said this") == nil)
        #expect(html("Yes.\n\n> they said this") == nil)
    }

    @Test func aQuotedReplyStaysAQuoteOnceSomethingIsFormatted() {
        let out = html("**Yes.**\n\n> they said this")
        #expect(out?.contains("<blockquote>") == true)
        #expect(out?.contains("<strong>Yes.</strong>") == true)
    }

    @Test func arithmeticIsNotEmphasis() {
        // 5*4*3 read as italics is how a naive scanner mangles a real sentence.
        #expect(html("5*4*3") == nil)
        #expect(html("the rate is 2*x") == nil)
    }

    @Test func emphasisStillWorksNextToPunctuation() {
        #expect(html("(*maybe*)")?.contains("<em>maybe</em>") == true)
        #expect(html("say \"*now*\"")?.contains("<em>now</em>") == true)
    }

    @Test func blankLinesSeparateParagraphs() {
        let out = html("**one**\n\ntwo")
        #expect((out?.components(separatedBy: "<p>").count ?? 0) >= 3)
    }

    // MARK: - Safety

    @Test func htmlInTheSourceIsEscaped() {
        // Typing markup must not inject it -- the body is user text, not source.
        let out = html("**bold** and <script>alert(1)</script>")
        #expect(out?.contains("&lt;script&gt;") == true)
        #expect(out?.contains("<script>") == false)
    }

    @Test func ampersandsAndAnglesSurviveAsText() {
        let out = html("**Tom & Jerry** <3")
        #expect(out?.contains("&amp;") == true)
        #expect(out?.contains("&lt;3") == true)
    }

    @Test func aJavascriptLinkIsNotLinked() {
        // Rendering it would be a hole in the recipient's client, not ours.
        let out = html("**x** [click](javascript:alert(1))")
        #expect(out?.contains("javascript:") == false)
    }
}
