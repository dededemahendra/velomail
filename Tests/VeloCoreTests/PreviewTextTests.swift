import Testing
import Foundation
@testable import VeloCore

/// Marketing mail pads its preheader with invisible characters so a client
/// cannot show any more of the message than the sender intends. Gmail hands
/// them through in the snippet, and they draw nothing while still taking up
/// room: a real row read "Review your plugins and themes", then a gap the
/// width of the list, then a stranded ellipsis.
///
/// Taken from an actual message in the mailbox -- zero-width non-joiners,
/// byte-order marks and combining grapheme joiners, separated by spaces.
@Suite struct PreviewTextTests {
    private let padded = "Review your plugins and themes"
        + String(repeating: " \u{034F} \u{200C} \u{FEFF}", count: 30)

    @Test func invisiblePaddingIsRemoved() {
        #expect(HTMLText.preview(padded) == "Review your plugins and themes")
    }

    @Test func everyShapeOfInvisibleCharacterGoes() {
        // Zero-width space, non-joiner, joiner, word joiner, BOM, soft hyphen,
        // combining grapheme joiner, and the left-to-right/right-to-left marks.
        let zoo = "a\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\u{00AD}\u{034F}\u{200E}\u{200F}b"
        #expect(HTMLText.preview(zoo) == "ab")
    }

    @Test func theRunsOfSpaceTheyLeaveBehindCollapse() {
        // Stripping the characters alone would leave "themes            " --
        // still a wide empty tail.
        #expect(HTMLText.preview("one \u{200C}  \u{200C}   two") == "one two")
    }

    @Test func ordinaryTextIsUntouched() {
        #expect(HTMLText.preview("Deployment status changed for mornington-green")
                    == "Deployment status changed for mornington-green")
    }

    /// It still has to decode entities, which is what the snippet path did
    /// before: without it the list reads "It&#39;s Friday".
    @Test func entitiesAreStillDecoded() {
        #expect(HTMLText.preview("It&#39;s Friday") == "It's Friday")
    }

    @Test func aSnippetOfNothingButPaddingComesOutEmpty() {
        #expect(HTMLText.preview(" \u{200C} \u{FEFF} \u{034F} ").isEmpty)
    }

    /// Non-Latin text must survive: these are format characters, not scripts.
    @Test func otherScriptsAreNotStripped() {
        #expect(HTMLText.preview("中文テスト mixed") == "中文テスト mixed")
        #expect(HTMLText.preview("Café — naïve") == "Café — naïve")
    }
}
