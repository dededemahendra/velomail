import Testing
import Foundation
@testable import VeloCore

@Suite struct MarkdownFormattingTests {
    private func apply(_ style: MarkdownFormatting.Style, to text: String,
                       _ range: Range<Int>) -> (String, Range<Int>) {
        let result = MarkdownFormatting.apply(style, to: text, selecting: range)
        return (result.text, result.selection)
    }

    // MARK: - Wrapping a selection

    @Test func boldWrapsWhatIsSelected() {
        let (text, _) = apply(.bold, to: "make this loud", 5..<9)
        #expect(text == "make **this** loud")
    }

    @Test func theSelectionStaysOnTheSameWords() {
        // So a second press can un-bold it, and so typing continues in place.
        let (text, selection) = apply(.bold, to: "make this loud", 5..<9)
        let chars = Array(text)
        #expect(String(chars[selection]) == "this")
    }

    @Test func pressingTwiceTakesItBackOff() {
        // A toolbar button that only ever adds markers is a trap.
        let once = MarkdownFormatting.apply(.bold, to: "make this loud", selecting: 5..<9)
        let twice = MarkdownFormatting.apply(.bold, to: once.text, selecting: once.selection)
        #expect(twice.text == "make this loud")
    }

    @Test func italicAndCodeUseTheirOwnMarkers() {
        #expect(apply(.italic, to: "a word here", 2..<6).0 == "a *word* here")
        #expect(apply(.code, to: "run make now", 4..<8).0 == "run `make` now")
    }

    @Test func withNothingSelectedItLeavesMarkersToTypeBetween() {
        let (text, selection) = apply(.bold, to: "start ", 6..<6)
        #expect(text == "start ****")
        #expect(selection == 8..<8)          // between the pairs
    }

    // MARK: - Whole lines

    @Test func aBulletGoesOnTheLine() {
        #expect(apply(.bullet, to: "milk\neggs", 0..<4).0 == "- milk\neggs")
    }

    @Test func everyLineTouchedByTheSelectionGetsOne() {
        #expect(apply(.bullet, to: "milk\neggs", 0..<9).0 == "- milk\n- eggs")
    }

    @Test func pressingBulletTwiceRemovesIt() {
        let once = MarkdownFormatting.apply(.bullet, to: "milk", selecting: 0..<4)
        let twice = MarkdownFormatting.apply(.bullet, to: once.text, selecting: once.selection)
        #expect(twice.text == "milk")
    }

    @Test func numbersCountUpAcrossTheSelection() {
        #expect(apply(.numbered, to: "one\ntwo\nthree", 0..<13).0 == "1. one\n2. two\n3. three")
    }

    @Test func quotingPrefixesEachLine() {
        #expect(apply(.quote, to: "they said\nthis", 0..<14).0 == "> they said\n> this")
    }

    // MARK: - Links

    @Test func aLinkWrapsTheSelectionAndWaitsForTheURL() {
        let (text, selection) = apply(.link, to: "see the map", 8..<11)
        #expect(text == "see the [map]()")
        // The cursor lands where the address goes, which is the only part the
        // writer still has to supply.
        #expect(selection == 14..<14)
    }

    @Test func aSelectedURLBecomesItsOwnLink() {
        // Selecting an address and pressing link should not ask for an address.
        let (text, selection) = apply(.link, to: "go https://x.com now", 3..<16)
        #expect(text == "go [](https://x.com) now")
        #expect(selection == 4..<4)          // waiting for the words
    }

    // MARK: - Edge cases

    @Test func anEmptyDocumentIsSurvivable() {
        #expect(apply(.bold, to: "", 0..<0).0 == "****")
    }

    @Test func aSelectionPastTheEndIsClamped() {
        // AppKit can hand over a stale range after an edit.
        #expect(apply(.bold, to: "short", 0..<99).0 == "**short**")
    }
}
