import Testing
import Foundation
@testable import VeloCore

@Suite struct UnsubscribeTests {

    // MARK: - Parsing

    @Test func aSingleWebLinkIsParsed() {
        #expect(Unsubscribe.links(in: "<https://example.com/u/abc>")
                == [.web(URL(string: "https://example.com/u/abc")!)])
    }

    @Test func aSingleMailtoIsParsed() {
        #expect(Unsubscribe.links(in: "<mailto:leave@example.com>")
                == [.mailto(address: "leave@example.com", subject: nil, body: nil)])
    }

    @Test func bothLinksAreParsedInHeaderOrder() {
        let links = Unsubscribe.links(in: "<https://example.com/u/1>, <mailto:leave@example.com>")
        #expect(links.count == 2)
        #expect(links.first == .web(URL(string: "https://example.com/u/1")!))
        #expect(links.last == .mailto(address: "leave@example.com", subject: nil, body: nil))
    }

    @Test func aMailtoSubjectIsPercentDecoded() {
        #expect(Unsubscribe.links(in: "<mailto:l@x.com?subject=Unsubscribe%20me>")
                == [.mailto(address: "l@x.com", subject: "Unsubscribe me", body: nil)])
    }

    @Test func aMailtoBodyIsParsed() {
        #expect(Unsubscribe.links(in: "<mailto:l@x.com?subject=Go&body=please>")
                == [.mailto(address: "l@x.com", subject: "Go", body: "please")])
    }

    @Test func aPlusInAMailtoParameterStaysAPlus() {
        // RFC 6068: a mailto query is not a form encoding, so `+` is literal.
        #expect(Unsubscribe.links(in: "<mailto:l@x.com?subject=a+b>")
                == [.mailto(address: "l@x.com", subject: "a+b", body: nil)])
    }

    @Test func angleBracketsAreOptional() {
        // Real headers are not RFC-perfect, and a missing bracket should not
        // cost the user their unsubscribe.
        #expect(Unsubscribe.links(in: "mailto:leave@example.com")
                == [.mailto(address: "leave@example.com", subject: nil, body: nil)])
    }

    @Test func whitespaceAndNewlinesAreTolerated() {
        let links = Unsubscribe.links(in: "  <https://example.com/u/1> ,\n\t<mailto:l@x.com>  ")
        #expect(links.count == 2)
        #expect(links.last == .mailto(address: "l@x.com", subject: nil, body: nil))
    }

    @Test func anUnknownSchemeIsSkippedRatherThanFailingTheHeader() {
        let links = Unsubscribe.links(in: "<ftp://example.com/u>, <mailto:l@x.com>")
        #expect(links == [.mailto(address: "l@x.com", subject: nil, body: nil)])
    }

    @Test func anEmptyHeaderHasNoLinks() {
        #expect(Unsubscribe.links(in: "").isEmpty)
        #expect(Unsubscribe.links(in: "   ").isEmpty)
    }

    @Test func aHeaderWithNothingUsableHasNoLinks() {
        #expect(Unsubscribe.links(in: "<>, not-a-link").isEmpty)
    }

    // MARK: - Preference

    @Test func mailtoIsPreferredOverTheWebLink() {
        // A channel the sender declared, that works without a browser, and that
        // Cmd+Z can take back because it goes through the outbound queue.
        #expect(Unsubscribe.preferred(in: "<https://example.com/u/1>, <mailto:l@x.com>")
                == .mailto(address: "l@x.com", subject: nil, body: nil))
    }

    @Test func theWebLinkIsUsedWhenThereIsNoMailto() {
        #expect(Unsubscribe.preferred(in: "<https://example.com/u/1>")
                == .web(URL(string: "https://example.com/u/1")!))
    }

    @Test func anEmptyHeaderHasNoPreferredLink() {
        #expect(Unsubscribe.preferred(in: "") == nil)
    }

    // MARK: - The draft

    @Test func aDraftIsBuiltFromAMailtoLink() {
        let draft = Unsubscribe.draft(for: .mailto(address: "l@x.com", subject: nil, body: nil))
        #expect(draft?.to == ["l@x.com"])
        #expect(draft?.subject == "Unsubscribe")
        #expect(draft?.bodyText == "Unsubscribe")
    }

    @Test func aDraftUsesTheHeadersSubjectAndBodyWhenItHasThem() {
        // Some list servers match on the exact subject they asked for.
        let draft = Unsubscribe.draft(for: .mailto(address: "l@x.com",
                                                   subject: "leave list-42",
                                                   body: "confirm"))
        #expect(draft?.subject == "leave list-42")
        #expect(draft?.bodyText == "confirm")
    }

    @Test func aDraftIsANewThreadNotAReply() {
        let draft = Unsubscribe.draft(for: .mailto(address: "l@x.com", subject: nil, body: nil))
        #expect(draft?.threadID == nil)
        #expect(draft?.inReplyTo == nil)
    }

    @Test func aWebLinkHasNoDraft() {
        // Completing a web unsubscribe form is not something a mail client can
        // do on the user's behalf.
        #expect(Unsubscribe.draft(for: .web(URL(string: "https://example.com/u/1")!)) == nil)
    }
}
