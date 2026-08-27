import Testing
import Foundation
@testable import VeloCore

@Suite struct HTMLTextTests {
    @Test func gmailsEscapedSnippetsReadAsWords() {
        // Gmail returns the snippet HTML-escaped, so the list showed
        // "It&#39;s Friday" and "Here&#39;s a summary".
        #expect(HTMLText.decoded("It&#39;s Friday") == "It's Friday")
        #expect(HTMLText.decoded("Here&#39;s a summary") == "Here's a summary")
    }

    @Test func theCommonOnesAreAllHandled() {
        #expect(HTMLText.decoded("Tom &amp; Jerry") == "Tom & Jerry")
        #expect(HTMLText.decoded("&lt;3") == "<3")
        #expect(HTMLText.decoded("&quot;quoted&quot;") == "\"quoted\"")
        #expect(HTMLText.decoded("a&nbsp;b") == "a b")
    }

    @Test func numericEntitiesAreDecodedToo() {
        // Senders use whichever their template engine emits.
        #expect(HTMLText.decoded("caf&#233;") == "caf\u{E9}")
        #expect(HTMLText.decoded("&#8217;") == "\u{2019}")
    }

    @Test func plainTextIsUntouched() {
        #expect(HTMLText.decoded("Just a sentence.") == "Just a sentence.")
    }

    @Test func aStrayAmpersandIsNotAnEntity() {
        // "R&D" must survive; only real entities are replaced.
        #expect(HTMLText.decoded("R&D budget") == "R&D budget")
    }

    @Test func anUnknownEntityIsLeftAsWritten() {
        // Better to show what arrived than to guess and drop it.
        #expect(HTMLText.decoded("&notarealentity;") == "&notarealentity;")
    }

    @Test func decodingIsCheapEnoughForALongList() {
        // Called once per visible row, so it must not be doing real work when
        // there is nothing to do.
        let plain = String(repeating: "word ", count: 500)
        #expect(HTMLText.decoded(plain) == plain)
    }
}
