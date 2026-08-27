import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ShortcutsCardTests {
    @Test func theCardIsReadOutOfTheKeymap() {
        // Written beside the keymap it would drift; read out of it, it cannot.
        let listed = KeyboardEngine.everyShortcut
        #expect(listed.contains { $0.action == .archiveSelected && $0.keys == "E" })
        #expect(listed.contains { $0.action == .goToInbox && $0.keys == "G I" })
    }

    @Test func nothingBoundIsLeftOff() {
        // The complement of the palette audit: a key with no row on the card
        // is a key nobody finds.
        let listed = Set(KeyboardEngine.everyShortcut.map(\.action))
        for action in MailAction.allCases where KeyboardEngine.shortcutLabel(for: action) != nil {
            #expect(listed.contains(action), "\(action) is bound but not listed")
        }
    }

    @Test func nothingUnboundIsInvented() {
        for shortcut in KeyboardEngine.everyShortcut {
            #expect(!shortcut.keys.isEmpty)
        }
    }

    @Test func theOrderIsStable() {
        // Built from a dictionary, which has none of its own.
        #expect(KeyboardEngine.everyShortcut.map(\.action)
                == KeyboardEngine.everyShortcut.map(\.action))
        let keys = KeyboardEngine.everyShortcut.map(\.action.rawValue)
        #expect(keys == keys.sorted())
    }

    @Test func itIsReachable() {
        #expect(CommandRegistry.v1.commands.map(\.title).contains("Keyboard shortcuts"))
    }
}

@Suite struct ShortcutColumnTests {
    private func split(_ counts: [Int]) -> (left: [Int], right: [Int]) {
        ShortcutsView.columns(counts) { $0 }
    }

    @Test func aTallSectionAndAShortOneDoNotSitSideBySide() {
        // A grid aligns by row, so a section of one sat beside a section of
        // seven and left the gap between them.
        let (left, right) = split([8, 5, 7, 1])
        #expect(!left.isEmpty && !right.isEmpty)
        let difference = abs(left.reduce(0, +) - right.reduce(0, +))
        #expect(difference <= 5, "columns differ by \(difference)")
    }

    @Test func nothingIsLostOrDuplicated() {
        let (left, right) = split([8, 5, 7, 1, 4])
        #expect(left + right == [8, 5, 7, 1, 4])
    }

    @Test func oneSectionGoesLeft() {
        let (left, right) = split([6])
        #expect(left == [6])
        #expect(right.isEmpty)
    }

    @Test func oneTallSectionDoesNotEndUpAloneAgainstThreeShortOnes() {
        // Exactly what filling the left column until it looked full produced:
        // triage, write and go on the left, against three small groups.
        let (left, right) = split([9, 6, 10, 2, 5, 3])
        let difference = abs(left.reduce(0, +) - right.reduce(0, +))
        #expect(difference <= 6, "columns differ by \(difference): \(left) | \(right)")
    }

    @Test func nothingIsHandledWithoutCrashing() {
        let (left, right) = split([])
        #expect(left.isEmpty && right.isEmpty)
    }
}
