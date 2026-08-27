import Testing
import Foundation
@testable import VeloCore

@Suite struct SearchOperatorTests {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)   // 17 Aug 2026
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func parse(_ text: String) -> SearchQuery {
        SearchQuery.parse(text, now: now, calendar: calendar)
    }

    // MARK: - Plain text

    @Test func wordsWithNoOperatorAreJustWords() {
        #expect(parse("open day somerville") == SearchQuery(terms: "open day somerville"))
    }

    @Test func nothingTypedMatchesNothing() {
        #expect(parse("   ").isEmpty)
    }

    // MARK: - Who it is from

    @Test func fromNarrowsToASender() {
        let query = parse("from:cloudflare")
        #expect(query.from == "cloudflare")
        #expect(query.terms.isEmpty)
    }

    @Test func fromSitsAlongsideWords() {
        let query = parse("deployment from:cloudflare failed")
        #expect(query.from == "cloudflare")
        #expect(query.terms == "deployment failed")
    }

    @Test func aQuotedSenderKeepsItsSpaces() {
        // from:"team tailscale" is one sender, not a sender and a word.
        let query = parse("from:\"team tailscale\"")
        #expect(query.from == "team tailscale")
        #expect(query.terms.isEmpty)
    }

    // MARK: - State

    @Test func isUnreadNarrowsToUnread() {
        #expect(parse("is:unread").isUnread == true)
    }

    @Test func isReadNarrowsTheOtherWay() {
        #expect(parse("is:read").isUnread == false)
    }

    // MARK: - Dates

    @Test func beforeAndAfterTakeADate() {
        let query = parse("after:2026-08-01 before:2026-08-15")
        #expect(query.after == calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        #expect(query.before == calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
    }

    @Test func plainEnglishSpansWork() {
        // "after:yesterday" is what someone types before they learn the format.
        let yesterday = calendar.startOfDay(for: now.addingTimeInterval(-86_400))
        #expect(parse("after:yesterday").after == yesterday)
    }

    @Test func aWeekAndAMonthAreUnderstood() {
        #expect(parse("after:week").after != nil)
        #expect(parse("after:month").after != nil)
        #expect(parse("after:week").after! > parse("after:month").after!)
    }

    @Test func anUnparseableDateIsLeftAsWords() {
        // Better to search for what was typed than to silently ignore it.
        let query = parse("after:soon")
        #expect(query.after == nil)
        #expect(query.terms == "after:soon")
    }

    // MARK: - Together

    @Test func operatorsCombine() {
        let query = parse("from:cloudflare is:unread after:2026-08-01 mornington")
        #expect(query.from == "cloudflare")
        #expect(query.isUnread == true)
        #expect(query.after != nil)
        #expect(query.terms == "mornington")
    }

    @Test func caseDoesNotMatterForTheOperator() {
        #expect(parse("From:Cloudflare").from == "Cloudflare")
        #expect(parse("IS:UNREAD").isUnread == true)
    }

    @Test func anOperatorWithNothingAfterItIsJustText() {
        // "from:" alone is someone mid-typing, not a filter on the empty sender.
        let query = parse("from:")
        #expect(query.from == nil)
        #expect(query.terms == "from:")
    }

    @Test func aColonInsideAWordIsNotAnOperator() {
        #expect(parse("re: deployment").terms == "re: deployment")
    }

    // MARK: - Which query wins

    @Test func aTypedOperatorIsRecognisedAsOne() {
        #expect(parse("from:cloudflare").hasOperators)
        #expect(parse("is:unread").hasOperators)
    }

    @Test func plainWordsAreNotOperators() {
        // Those are the ones worth handing to a model to interpret.
        #expect(!parse("mail from natalie last week").hasOperators)
    }

    @Test func theTranslatorLeavesATypedQueryAlone() async {
        // Someone who writes from:cloudflare has said exactly what they want.
        // Asking a model to reinterpret it can only make it worse, and costs a
        // round trip to do so.
        let translator = QueryTranslator(assistant: MailAssistant(provider: LoudProvider()),
                                         now: { self.now })

        let query = await translator.translate("from:cloudflare is:unread")

        #expect(query.from == "cloudflare")
        #expect(query.isUnread == true)
    }
}

/// Fails if asked: a typed query should never reach a model.
private struct LoudProvider: LLMProvider {
    var displayName: String { "loud" }
    func complete(_ request: LLMRequest) async throws -> String {
        Issue.record("a typed query was sent to the model")
        return "{}"
    }
}
