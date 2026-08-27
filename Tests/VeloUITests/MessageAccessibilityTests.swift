import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct MessageAccessibilityTests {
    private func message(sender: String = "Cloudflare <noreply@cf.com>",
                         body: String = "Deployment status changed") -> Message {
        Message(id: "m", threadID: "t", sender: sender, recipients: [], subject: "s",
                date: Date(timeIntervalSince1970: 1_787_000_000), bodyHTML: nil,
                bodyText: body, isUnread: false, labelIDs: [])
    }

    private func spoken(_ message: Message, expanded: Bool = false) -> String {
        MailFormatting.messageDescription(message, time: "09:41", isExpanded: expanded)
    }

    @Test func aMessageNamesItsSenderEvenWhenTheScreenDoesNot() {
        // The transcript hides a repeated sender, which is right on screen and
        // wrong out loud: a listener has no row above to have read it from.
        #expect(spoken(message()).hasPrefix("From Cloudflare"))
    }

    @Test func itSaysWhatTheMessageSays() {
        #expect(spoken(message()).contains("Deployment status changed"))
    }

    @Test func aLongMessageIsNotReadInFull() {
        // The body is a summary here; the message itself is one keystroke away.
        let long = String(repeating: "word ", count: 200)
        #expect(spoken(message(body: long)).count < 200)
    }

    @Test func aCollapsedMessageSaysSo() {
        #expect(spoken(message()).hasSuffix("collapsed"))
        #expect(!spoken(message(), expanded: true).hasSuffix("collapsed"))
    }

    @Test func anEmptyMessageStillNamesItsSenderAndTime() {
        let description = spoken(message(body: ""))
        #expect(description.contains("Cloudflare"))
        #expect(description.contains("09:41"))
    }
}
