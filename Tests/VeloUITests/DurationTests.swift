import Testing
import Foundation
@testable import VeloUI

@Suite struct DurationTests {
    private func text(_ seconds: TimeInterval?) -> String { AnalyticsView.duration(seconds) }

    @Test func aNinetyMinuteMedianIsNotTwoHours() {
        // It rounded to one unit, so 1h30m read as "2h" -- a third out, on the
        // one number anyone would quote.
        #expect(text(5_400) == "1h 30m")
    }

    @Test func aQuarterPastIsNotLostEither() {
        #expect(text(4_500) == "1h 15m")
    }

    @Test func aCleanHourStaysClean() {
        #expect(text(3_600) == "1h")
    }

    @Test func minutesAreStillJustMinutes() {
        #expect(text(1_800) == "30m")
        #expect(text(3_599) == "59m")
    }

    @Test func secondsAreNotRoundedAwayToZeroMinutes() {
        // "0m" for a reply that took eight seconds says less than "8s".
        #expect(text(8) == "8s")
    }

    @Test func daysCarryTheirHours() {
        #expect(text(86_400 + 7_200) == "1d 2h")
        #expect(text(86_400) == "1d")
    }

    @Test func nothingRepliedToIsADash() {
        #expect(text(nil) == "\u{2014}")
    }

    @Test func aNegativeSpanIsNotDrawnAsATime() {
        // A reply timestamped before the message it answers is a clock
        // problem, not a minus-two-hour response time.
        #expect(text(-60) == "\u{2014}")
    }
}

@Suite struct FullStampTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }()

    private func at(_ iso: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.calendar = cal
        f.timeZone = cal.timeZone
        return f.date(from: iso)!
    }

    @Test func theFullDateIsAvailableSomewhere() {
        // The transcript said "Yesterday" and "17.28" and nowhere at all what
        // date that actually was.
        let stamp = MailFormatting.fullStamp(at("2026-08-27 17:28"), calendar: cal)
        #expect(stamp.contains("2026"))
        #expect(stamp.contains("27"))
    }

    @Test func itNamesTheDayAsWellAsTheDate() {
        // Reading "Thursday" beside a relative "Yesterday" is what makes the
        // tooltip worth opening.
        let stamp = MailFormatting.fullStamp(at("2026-08-27 09:00"), calendar: cal)
        #expect(stamp.lowercased().contains("thursday"))
    }

    @Test func theTimeIsThereToo() {
        let stamp = MailFormatting.fullStamp(at("2026-08-27 17:28"), calendar: cal)
        #expect(stamp.contains("28"))
    }
}
