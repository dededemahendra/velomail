import Testing
import Foundation
@testable import VeloCore

@Suite struct SenderRollupTests {
    private func row(_ sender: String, unread: Bool = false, unsub: Bool = false,
                     day: Int = 0) -> SenderRollup.Row {
        SenderRollup.Row(sender: sender, isUnread: unread, canUnsubscribe: unsub,
                         date: Date(timeIntervalSince1970: Double(day) * 86_400))
    }

    // MARK: - Who is who

    @Test func theAddressIsTheIdentityNotTheName() {
        // Bulk senders vary the friendly name on every send.
        let rolled = SenderRollup.summarise([
            row("Xero <billing@xero.com>"),
            row("Xero Invoices <billing@xero.com>"),
            row("<BILLING@Xero.com>"),
        ])
        #expect(rolled.count == 1)
        #expect(rolled[0].threads == 3)
    }

    @Test func theRichestNameWins() {
        // One bare noreply@ must not erase a full name seen a message earlier.
        let rolled = SenderRollup.summarise([
            row("Peta Bilston <peta@example.com>"),
            row("peta@example.com"),
        ])
        #expect(rolled[0].name == "Peta Bilston")
    }

    @Test func aSenderWhoNeverGaveANameShowsTheirAddress() {
        let rolled = SenderRollup.summarise([row("noreply@example.com")])
        #expect(rolled[0].displayName == "noreply@example.com")
    }

    @Test func somethingThatIsNotAnAddressIsNotASender() {
        #expect(SenderRollup.summarise([row("Mailer Daemon")]).isEmpty)
    }

    // MARK: - The counts

    @Test func unreadIsCountedPerSender() {
        let rolled = SenderRollup.summarise([
            row("a@x.com", unread: true), row("a@x.com", unread: true),
            row("a@x.com"), row("b@x.com", unread: true),
        ])
        #expect(rolled[0].address == "a@x.com")
        #expect(rolled[0].threads == 3)
        #expect(rolled[0].unread == 2)
    }

    @Test func oneUnsubscribableMessageMakesTheSenderLeavable() {
        // The header is on the message, not the sender, and bulk senders do
        // not always set it.
        let rolled = SenderRollup.summarise([row("a@x.com"), row("a@x.com", unsub: true)])
        #expect(rolled[0].canUnsubscribe)
    }

    @Test func theNewestDateWins() {
        let rolled = SenderRollup.summarise([row("a@x.com", day: 5), row("a@x.com", day: 2)])
        #expect(rolled[0].newest == Date(timeIntervalSince1970: 5 * 86_400))
    }

    // MARK: - The order

    @Test func theBusiestComeFirst() {
        // The whole point: who is filling the mailbox.
        let rolled = SenderRollup.summarise(
            Array(repeating: row("loud@x.com"), count: 9) + [row("quiet@x.com")])
        #expect(rolled.map(\.address) == ["loud@x.com", "quiet@x.com"])
    }

    @Test func twoOfEqualWeightDoNotWobble() {
        // Same count and same date: the address decides, so the list is the
        // same list every time it is drawn.
        let rolled = SenderRollup.summarise([row("b@x.com"), row("a@x.com")])
        #expect(rolled.map(\.address) == ["a@x.com", "b@x.com"])
    }

    @Test func recencyBreaksATieOnVolume() {
        let rolled = SenderRollup.summarise([row("a@x.com", day: 1), row("b@x.com", day: 9)])
        #expect(rolled[0].address == "b@x.com")
    }

    // MARK: - Share

    @Test func aSenderKnowsHowMuchOfTheMailboxIsTheirs() {
        // 84% of this mailbox is ten senders, and nothing said so.
        let rolled = SenderRollup.summarise(Array(repeating: row("a@x.com"), count: 41))
        #expect(abs(rolled[0].share(of: 100) - 0.41) < 0.001)
    }

    @Test func anEmptyMailboxIsNotADivisionByZero() {
        let rolled = SenderRollup.summarise([row("a@x.com")])
        #expect(rolled[0].share(of: 0) == 0)
    }
}
