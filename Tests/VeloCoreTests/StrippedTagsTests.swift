import Testing
import Foundation
@testable import VeloCore

@Suite struct StrippedTagsTests {
    private func strip(_ html: String) -> String { QuotedReply.strippedTags(html) }

    // MARK: - Blocks whose content is not prose

    @Test func aStylesheetGoesWithItsTags() {
        // Removing `<style>` and `</style>` as tags leaves the CSS between them
        // standing as text. A newsletter carries kilobytes of @font-face rules,
        // and that is what filled the quote.
        let html = "<style>@font-face{font-family:'Lato';src:url('https://cdn/x.woff2')}</style><p>Hello</p>"

        #expect(strip(html) == "Hello")
    }

    @Test func aScriptGoesTheSameWay() {
        #expect(strip("<script>var a = 1 < 2;</script><p>Hi</p>") == "Hi")
    }

    @Test func headMatterIsNotProseEither() {
        let html = "<head><title>Ignore me</title><meta charset=\"utf-8\"></head><body><p>Read me</p></body>"

        #expect(strip(html) == "Read me")
    }

    @Test func theyGoEvenWithAttributesOnTheOpeningTag() {
        // Real mail writes <style type="text/css" media="all">.
        let html = "<style type=\"text/css\" media=\"all\">.a{color:red}</style><p>Hello</p>"

        #expect(strip(html) == "Hello")
    }

    @Test func anUnclosedStyleDoesNotEatTheMessage() {
        // Malformed markup is normal in mail; losing the body over it is not.
        #expect(strip("<p>Kept</p><style>.a{color:red}").contains("Kept"))
    }

    @Test func caseDoesNotMatter() {
        #expect(strip("<STYLE>.a{color:red}</STYLE><p>Hello</p>") == "Hello")
    }

    // MARK: - What is left should read as prose

    @Test func blockElementsBecomeLineBreaks() {
        // Without this every paragraph runs into the next one.
        #expect(strip("<p>One</p><p>Two</p>") == "One\nTwo")
    }

    @Test func entitiesAreDecoded() {
        #expect(strip("<p>Tom &amp; Jerry &lt;3 &quot;quotes&quot; &#39;n&#39; things</p>")
                == "Tom & Jerry <3 \"quotes\" 'n' things")
    }

    @Test func runsOfWhitespaceCollapse() {
        // HTML source is indented; the reader never sees that.
        #expect(strip("<p>One     \n     Two</p>") == "One Two")
    }

    @Test func plainProseSurvivesUntouched() {
        #expect(strip("<p>Just a sentence.</p>") == "Just a sentence.")
    }

    // MARK: - Characters meant never to be seen

    @Test func preheaderPaddingIsRemoved() {
        // Newsletters pad the inbox preview line with hundreds of invisible
        // characters. They are invisible in a mail client and were not in
        // ours, so a quote opened with a wall of them.
        let padded = "Real words." + String(repeating: "\u{034F}\u{00AD}\u{200B}", count: 50)

        #expect(strip("<p>\(padded)</p>") == "Real words.")
    }

    @Test func theirEntityFormsGoTheSameWay() {
        #expect(strip("<p>Words&shy;&zwnj;&zwj;</p>") == "Words")
    }

    @Test func aByteOrderMarkIsNotContent() {
        #expect(strip("<p>\u{FEFF}Words</p>") == "Words")
    }

    @Test func ordinaryPunctuationIsUntouched() {
        // The removal is of invisibles, not of anything unusual.
        #expect(strip("<p>caf\u{00E9} \u{2014} na\u{00EF}ve \u{2018}quoted\u{2019}</p>")
                == "caf\u{00E9} \u{2014} na\u{00EF}ve \u{2018}quoted\u{2019}")
    }
}
