import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct TranscriptGroupingTests {
    private func message(_ sender: String, _ seconds: TimeInterval,
                         body: String = "b") -> Message {
        Message(id: "m\(seconds)", threadID: "t", sender: sender, recipients: [],
                subject: "s", date: Date(timeIntervalSince1970: seconds),
                bodyHTML: nil, bodyText: body, isUnread: false, labelIDs: [])
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    // MARK: - Repeating the sender

    @Test func theFirstMessageAlwaysNamesItsSender() {
        let rows = TranscriptRows.build([message("Cloudflare", 100)], calendar: calendar)
        #expect(rows.first?.showsSender == true)
    }

    @Test func aRunFromOneSenderNamesThemOnce() {
        // Twelve deployment alerts do not need the word "Cloudflare" twelve
        // times; the only thing that varies is the time.
        let rows = TranscriptRows.build(
            (0..<5).map { message("Cloudflare", 100 + Double($0) * 60) }, calendar: calendar)

        #expect(rows.map(\.showsSender) == [true, false, false, false, false])
    }

    @Test func aDifferentSenderIsNamedAgain() {
        let rows = TranscriptRows.build([message("Cloudflare", 100),
                                         message("Alice", 160),
                                         message("Cloudflare", 220)], calendar: calendar)

        #expect(rows.map(\.showsSender) == [true, true, true])
    }

    @Test func aNewDayNamesTheSenderAgain() {
        // After a date separator the run has visibly restarted, and a row with
        // no name under a fresh heading reads as orphaned.
        let rows = TranscriptRows.build([message("Cloudflare", 100),
                                         message("Cloudflare", 100 + 86_400)],
                                        calendar: calendar)

        #expect(rows.map(\.showsSender) == [true, true])
    }

    // MARK: - Dates

    @Test func theFirstMessageCarriesItsDate() {
        let rows = TranscriptRows.build([message("Cloudflare", 100)], calendar: calendar)
        #expect(rows.first?.dayHeading != nil)
    }

    @Test func messagesOnTheSameDayShareOneHeading() {
        // A full date on every row is twelve copies of the same fact.
        let rows = TranscriptRows.build([message("Cloudflare", 100),
                                         message("Cloudflare", 3_700)], calendar: calendar)

        #expect(rows[0].dayHeading != nil)
        #expect(rows[1].dayHeading == nil)
    }

    @Test func aNewDayGetsItsOwnHeading() {
        let rows = TranscriptRows.build([message("Cloudflare", 100),
                                         message("Cloudflare", 100 + 86_400)],
                                        calendar: calendar)

        #expect(rows[1].dayHeading != nil)
    }

    @Test func aRowShowsTheTimeAndNotTheDate() {
        // The date is on the heading above it; repeating it is noise.
        let rows = TranscriptRows.build([message("Cloudflare", 45_296)], calendar: calendar)

        #expect(rows[0].time.contains(":") || rows[0].time.contains("."))
        #expect(!rows[0].time.contains("2026"))
    }

    // MARK: - Nothing to group

    @Test func anEmptyThreadIsSurvivable() {
        #expect(TranscriptRows.build([], calendar: calendar).isEmpty)
    }

    @Test func aSingleMessageThreadIsUnchangedByAnyOfThis() {
        let rows = TranscriptRows.build([message("Alice", 100)], calendar: calendar)
        #expect(rows.count == 1)
        #expect(rows[0].showsSender)
        #expect(rows[0].dayHeading != nil)
    }

    // MARK: - Repeating the same words

    @Test func anIdenticalPreviewIsShownOnce() {
        // Nine deployment alerts that all say "status changed to success" say
        // it once; what varies is the time, and that is what should be read.
        let rows = TranscriptRows.build(
            (0..<4).map { message("Cloudflare", 100 + Double($0) * 60, body: "same") },
            calendar: calendar)

        #expect(rows.map(\.showsPreview) == [true, false, false, false])
    }

    @Test func aDifferentPreviewIsShown() {
        let rows = TranscriptRows.build([message("Cloudflare", 100, body: "one"),
                                         message("Cloudflare", 160, body: "two")],
                                        calendar: calendar)

        #expect(rows.map(\.showsPreview) == [true, true])
    }

    @Test func aNewSenderAlwaysShowsWhatTheySaid() {
        // Even by coincidence saying the same thing: it is a different person
        // speaking, and a row with only a time under a new name says nothing.
        let rows = TranscriptRows.build([message("Cloudflare", 100, body: "same"),
                                         message("Alice", 160, body: "same")],
                                        calendar: calendar)

        #expect(rows.map(\.showsPreview) == [true, true])
    }
}
