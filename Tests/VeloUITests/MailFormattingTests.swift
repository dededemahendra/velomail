import Testing
import Foundation
@testable import VeloUI

@Suite struct MailFormattingTests {
    /// A fixed reference so "today" and "this week" mean something stable.
    /// Thursday 27 August 2026, 17:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_787_850_000)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func relative(_ offset: TimeInterval) -> String {
        MailFormatting.relativeDate(now.addingTimeInterval(offset), now: now, calendar: calendar)
    }

    @Test func todayShowsTheTime() {
        // What you want at a glance for mail that arrived this morning.
        let text = relative(-3 * 3600)
        #expect(text.contains(":") || text.contains("."))
        #expect(!text.lowercased().contains("aug"))
    }

    @Test func yesterdayIsNamed() {
        #expect(relative(-26 * 3600) == "Yesterday")
    }

    @Test func earlierThisWeekIsAWeekday() {
        // Two days back from Thursday 27 Aug is Tuesday 25 Aug.
        #expect(relative(-2 * 86_400) == "Tuesday")
    }

    @Test func sixDaysBackIsStillAWeekday() {
        #expect(relative(-6 * 86_400).count > 5)
        #expect(!relative(-6 * 86_400).contains("/"))
    }

    @Test func olderThisYearIsADayAndMonth() {
        let text = relative(-40 * 86_400)
        #expect(text.contains("Jul") || text.contains("Jun"))
        #expect(!text.contains("2026"))     // the year is noise within the year
    }

    @Test func lastYearCarriesTheYear() {
        let text = relative(-400 * 86_400)
        #expect(text.contains("2025"))
    }

    @Test func aFutureDateDoesNotClaimToBeYesterday() {
        // Clock skew and scheduled sends both produce these.
        #expect(relative(3600) != "Yesterday")
    }

    @Test func theBoundaryBetweenTodayAndYesterdayIsCalendarBasedNot24Hours() {
        // 01:00 today and 23:00 yesterday are 2 hours apart but different days.
        let earlyToday = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: now)!
        let lateYesterday = earlyToday.addingTimeInterval(-2 * 3600)

        #expect(MailFormatting.relativeDate(earlyToday, now: now, calendar: calendar) != "Yesterday")
        #expect(MailFormatting.relativeDate(lateYesterday, now: now, calendar: calendar) == "Yesterday")
    }

    // MARK: - Names

    @Test func aDisplayNameBeatsTheAddress() {
        #expect(MailFormatting.displayName("Natalie Roberts <natalie@x.co>") == "Natalie Roberts")
    }

    @Test func aBareAddressIsShownAsIs() {
        #expect(MailFormatting.displayName("bare@example.com") == "bare@example.com")
    }

    @Test func surroundingQuotesAreDropped() {
        // Headers routinely arrive as "Roberts, Natalie" <natalie@x.co>.
        #expect(MailFormatting.displayName("\"Roberts, Natalie\" <natalie@x.co>") == "Roberts, Natalie")
    }

    @Test func anEmptyDisplayNameFallsBackToTheAddress() {
        #expect(MailFormatting.displayName(" <bare@example.com>") == "bare@example.com")
    }

    // MARK: - When something comes back

    private func wake(_ offset: TimeInterval) -> String {
        MailFormatting.wakeTime(now.addingTimeInterval(offset), now: now, calendar: calendar)
    }

    @Test func laterTodayIsJustTheTime() {
        #expect(wake(2 * 3_600).contains("19"))
        #expect(!wake(2 * 3_600).lowercased().contains("tomorrow"))
    }

    @Test func tomorrowSaysSo() {
        // A bare "09:00" on a list of future times reads as today.
        #expect(wake(20 * 3_600).hasPrefix("Tomorrow"))
    }

    @Test func laterThisWeekNamesTheDay() {
        let out = wake(3 * 86_400)
        #expect(out.hasPrefix("Sun"))
        #expect(out.contains("17"))
    }

    @Test func beyondAWeekGivesTheDate() {
        #expect(wake(30 * 86_400).contains("Sep"))
    }

    @Test func aWakeTimeAlreadyPastReadsAsNow() {
        // A thread at its wake time is on its way back, not overdue.
        #expect(wake(-60) == "Now")
    }
}
