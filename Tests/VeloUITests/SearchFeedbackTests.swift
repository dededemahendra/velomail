import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct SearchFeedbackTests {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func describe(_ text: String) -> [String] {
        SearchQuery.parse(text, now: now, calendar: calendar)
            .filterLabels(calendar: calendar)
    }

    // MARK: - Saying what was understood

    @Test func aSenderFilterIsNamed() {
        // Without this there is no way to tell whether from:cloudflare
        // filtered, or searched for the literal string.
        #expect(describe("from:cloudflare") == ["From cloudflare"])
    }

    @Test func unreadIsNamed() {
        #expect(describe("is:unread") == ["Unread"])
        #expect(describe("is:read") == ["Read"])
    }

    @Test func datesAreNamedInTheFormTheyWereGiven() {
        #expect(describe("after:2026-08-01").first?.hasPrefix("After") == true)
        #expect(describe("before:2026-08-01").first?.hasPrefix("Before") == true)
    }

    @Test func severalFiltersAreAllNamed() {
        let labels = describe("from:cloudflare is:unread mornington")
        #expect(labels == ["From cloudflare", "Unread"])
    }

    @Test func plainWordsProduceNoLabels() {
        // Nothing was narrowed, so there is nothing to report.
        #expect(describe("mornington green").isEmpty)
    }

    @Test func anUnparsedOperatorIsNotClaimedAsAFilter() {
        // after:soon fell back to words; saying "After soon" would be a lie.
        #expect(describe("after:soon").isEmpty)
    }
}
