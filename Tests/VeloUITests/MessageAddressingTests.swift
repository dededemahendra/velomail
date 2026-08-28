import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct MessageAddressingTests {
    private let me = "gede@sistercreatives.co"

    // MARK: - The address

    @Test func theNameIsNotSaidTwice() {
        // It read "Asana" in bold and "Asana <no-reply@asana.com>" directly
        // underneath. The second one is repetition, not detail.
        #expect(MessageAddressing.address(of: "Asana <no-reply@asana.com>")
                == "no-reply@asana.com")
    }

    @Test func aBareAddressIsLeftAlone() {
        #expect(MessageAddressing.address(of: "no-reply@asana.com") == "no-reply@asana.com")
    }

    @Test func aSenderWithNoAddressKeepsTheirHeader() {
        // Better their raw header than an empty line.
        #expect(MessageAddressing.address(of: "Mailer Daemon") == "mailer daemon")
    }

    // MARK: - Who it went to

    @Test func yourOwnAddressIsNotReadBackAtYou() {
        // It printed "→ gede@sistercreatives.co" at the person who is
        // gede@sistercreatives.co.
        #expect(MessageAddressing.recipients(to: [me], identity: me) == "to me")
    }

    @Test func theCaseAndTheDisplayNameDoNotChangeThat() {
        #expect(MessageAddressing.recipients(to: ["Gede <GEDE@SisterCreatives.co>"],
                                             identity: me) == "to me")
    }

    @Test func meAndOneOther() {
        #expect(MessageAddressing.recipients(to: [me, "peta@example.com"],
                                             identity: me) == "to me and 1 other")
    }

    @Test func meAndSeveral() {
        #expect(MessageAddressing.recipients(to: [me, "a@x.com", "b@x.com"],
                                             identity: me) == "to me and 2 others")
    }

    @Test func ccCountsAsBeingOnIt() {
        #expect(MessageAddressing.recipients(to: ["a@x.com"], cc: [me],
                                             identity: me) == "to me and 1 other")
    }

    @Test func aMessageNotAddressedToYouNamesWhoItWasFor() {
        // In Sent, or on a thread you were bcc'd into.
        #expect(MessageAddressing.recipients(to: ["Peta Bilston <peta@example.com>"],
                                             identity: me) == "to Peta Bilston")
    }

    @Test func severalOthersAreCounted() {
        #expect(MessageAddressing.recipients(to: ["Peta <peta@x.com>", "a@x.com", "b@x.com"],
                                             identity: me) == "to Peta and 2 others")
    }

    @Test func aMessageWithNoRecipientsSaysNothingAtAll() {
        // An empty "to" is worse than no line.
        #expect(MessageAddressing.recipients(to: [], identity: me) == nil)
        #expect(MessageAddressing.recipients(to: ["", "  "], identity: me) == nil)
    }

    // MARK: - The disc

    @Test func theInitialComesFromTheName() {
        #expect(MessageAddressing.initial(for: "Asana <no-reply@asana.com>") == "A")
    }

    @Test func aNamelessSenderUsesTheirAddress() {
        #expect(MessageAddressing.initial(for: "no-reply@asana.com") == "N")
    }

    @Test func punctuationIsSkippedRatherThanShown() {
        // A disc with a quotation mark in it looks like a rendering fault.
        #expect(MessageAddressing.initial(for: "\"Xero\" <billing@xero.com>") == "X")
    }

    @Test func somethingWithNoLettersAtAllStillGetsADisc() {
        #expect(MessageAddressing.initial(for: "<>") == "?")
    }

    @Test func oneCorrespondentIsOneColourForever() {
        // Not random: a colour that changed between launches would be worse
        // than no colour at all.
        let first = MessageAddressing.hue(for: "Asana <no-reply@asana.com>")
        #expect(MessageAddressing.hue(for: "no-reply@asana.com") == first)
        #expect(MessageAddressing.hue(for: "NO-REPLY@Asana.com") == first)
    }

    @Test func differentPeopleGetDifferentColours() {
        let hues = ["a@x.com", "b@x.com", "c@x.com", "peta@example.com"]
            .map { MessageAddressing.hue(for: $0) }
        #expect(Set(hues).count == 4)
    }

    @Test func aHueIsAHue() {
        for address in ["a@x.com", "", "zzz", "\u{1F600}@x.com"] {
            let hue = MessageAddressing.hue(for: address)
            #expect(hue >= 0 && hue < 1)
        }
    }
}
