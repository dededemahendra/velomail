import Testing
import Foundation
import AppKit
import VeloCore
@testable import VeloUI

@Suite struct KeyMonitorTests {
    private func keyDown(_ character: String, command: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero,
                         modifierFlags: command ? [.command] : [],
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: character, charactersIgnoringModifiers: character,
                         isARepeat: false, keyCode: 0)!
    }

    @Test func everyCharacterTheKeymapBindsSurvivesTranslation() {
        // The monitor used to allow letters, digits and "/" only, so a binding
        // on any other punctuation was silently unreachable -- Cmd+, for
        // settings was added, shipped and did nothing. Deriving the allowance
        // from the keymap is what stops that happening again.
        for character in KeyboardEngine.boundCharacters {
            let translated = KeyMonitor.translate(keyDown(String(character), command: true))
            #expect(translated != nil, "\(character) is bound but filtered out")
        }
    }

    @Test func aCommaReachesTheEngine() {
        #expect(KeyMonitor.translate(keyDown(",", command: true))
                == KeyInput(.character(","), [.command]))
    }

    @Test func lettersAndDigitsStillGetThrough() {
        #expect(KeyMonitor.translate(keyDown("e")) == KeyInput(.character("e")))
        #expect(KeyMonitor.translate(keyDown("2")) == KeyInput(.character("2")))
    }

    @Test func punctuationNothingIsBoundToIsStillIgnored() {
        // Passing everything would mean the monitor swallowing keys a text
        // field wanted.
        #expect(KeyMonitor.translate(keyDown("%")) == nil)
    }
}
