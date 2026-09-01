import Testing
import Foundation
@testable import VeloCore

/// A `mailto:` in a message used to be handed to the system, which opens
/// whatever the reader's default mail client is -- in a mail client, an odd
/// thing to do. It should open the composer that is already in front of them.
///
/// The link can carry more than an address, and senders use that: an
/// unsubscribe link is often `mailto:leave@list?subject=unsubscribe`, and
/// dropping the subject would send a message that does nothing.
@Suite struct MailtoLinkTests {
    private func parse(_ address: String) -> MailtoLink? {
        URL(string: address).flatMap(MailtoLink.init(url:))
    }

    @Test func aBareAddress() {
        let link = parse("mailto:someone@example.com")
        #expect(link?.to == ["someone@example.com"])
        #expect(link?.subject == nil)
        #expect(link?.body == nil)
    }

    @Test func severalAddressesSeparatedByCommas() {
        #expect(parse("mailto:a@x.com,b@y.com")?.to == ["a@x.com", "b@y.com"])
    }

    @Test func subjectAndBodyComeOffTheQuery() {
        let link = parse("mailto:list@example.com?subject=unsubscribe&body=please%20remove%20me")
        #expect(link?.to == ["list@example.com"])
        #expect(link?.subject == "unsubscribe")
        #expect(link?.body == "please remove me")
    }

    @Test func ccIsCarriedTooAndTheQueryNamesAreCaseInsensitive() {
        let link = parse("mailto:a@x.com?CC=c@z.com&Subject=Hello")
        #expect(link?.cc == ["c@z.com"])
        #expect(link?.subject == "Hello")
    }

    /// Percent-encoding is the norm in these, not an edge case: a space in a
    /// subject has to be encoded for the URL to parse at all.
    ///
    /// The `+` is the point of this one. Translating it to a space is the
    /// form-urlencoded convention and applies before percent-decoding; doing it
    /// afterwards eats a literal plus that arrived as `%2B`, and this subject
    /// came out as "invoice   receipt". RFC 6068 spells a space as `%20`.
    @Test func encodedCharactersAreDecoded() {
        let link = parse("mailto:a@x.com?subject=Re%3A%20your%20invoice%20%2B%20receipt")
        #expect(link?.subject == "Re: your invoice + receipt")
    }

    /// `mailto:?subject=...` with no recipient is legal and appears in
    /// share links. The composer should open with the subject and an empty To.
    @Test func anEmptyRecipientIsStillWorthOpening() {
        let link = parse("mailto:?subject=Look%20at%20this")
        #expect(link?.to == [])
        #expect(link?.subject == "Look at this")
    }

    @Test func anythingThatIsNotMailtoIsRefused() {
        #expect(parse("https://example.com") == nil)
        #expect(parse("tel:+61400000000") == nil)
    }

    /// Addresses arrive with whitespace around them often enough to matter.
    @Test func surroundingSpaceIsTrimmedAndEmptiesDropped() {
        #expect(parse("mailto:%20a@x.com%20,,%20b@y.com")?.to == ["a@x.com", "b@y.com"])
    }
}
