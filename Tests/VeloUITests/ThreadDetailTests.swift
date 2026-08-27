import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ThreadDetailTests {
    private func labels(_ ids: [String], known: [MailLabel]) -> [MailLabel] {
        ThreadDetail.labels(on: ids, known: known)
    }

    private let known = [
        MailLabel(id: "Label_7", name: "Clients", kind: .user),
        MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system),
        MailLabel(id: "INBOX", name: "INBOX", kind: .system),
    ]

    // MARK: - Which labels a thread shows

    @Test func aFiledThreadShowsWhatItWasFiledAs() {
        // Filing was possible and invisible: nothing anywhere said which
        // labels a thread carried.
        #expect(labels(["INBOX", "Label_7"], known: known).map(\.displayName) == ["Clients"])
    }

    @Test func theStructuralOnesAreNotWorthSaying() {
        // "Inbox" on a thread in the inbox, "Unread" on an unread one: both
        // are already obvious from where the reader is standing.
        #expect(labels(["INBOX", "UNREAD", "STARRED"], known: known).isEmpty)
    }

    @Test func aCategoryReadsAsAWord() {
        #expect(labels(["CATEGORY_UPDATES"], known: known).map(\.displayName) == ["Updates"])
    }

    @Test func aLabelWithNoNameYetIsNotShownAsAnID() {
        // Names arrive on the next sync; "Label_9" on screen is worse than
        // nothing at all.
        #expect(labels(["Label_9"], known: known).isEmpty)
    }

    @Test func aThreadWithNoLabelsShowsNothing() {
        #expect(labels(["INBOX"], known: known).isEmpty)
    }

    @Test func theyComeBackInTheSameOrderAsTheSidebar() {
        // Categories before a person's own, so a thread and the palette do not
        // disagree about the order of the same set.
        let many = known + [MailLabel(id: "Label_1", name: "Alpha", kind: .user)]
        #expect(labels(["Label_7", "CATEGORY_UPDATES", "Label_1"], known: many)
            .map(\.displayName) == ["Updates", "Alpha", "Clients"])
    }

    // MARK: - How many messages

    @Test func aThreadOfOneSaysNothingAboutItsLength() {
        // "1 message" is a fact nobody needed.
        #expect(ThreadDetail.messageCount(1) == nil)
    }

    @Test func alongerThreadSaysHowLong() {
        #expect(ThreadDetail.messageCount(9) == "9 messages")
    }
}

@Suite struct TranscriptHeadingTests {
    private let cal = Calendar(identifier: .gregorian)
    private func at(_ iso: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.calendar = cal
        f.timeZone = cal.timeZone
        return f.date(from: iso)!
    }

    @Test func todayIsCalledToday() {
        // It read as a clock time: the heading said "17.28" and the row
        // beneath it said "17.28" too -- the same string twice, one of them
        // claiming to be a day.
        #expect(MailFormatting.dayHeading(at("2026-08-27 17:28"),
                                          now: at("2026-08-27 19:00"), calendar: cal) == "Today")
    }

    @Test func theOtherDaysAreUnchanged() {
        #expect(MailFormatting.dayHeading(at("2026-08-26 09:00"),
                                          now: at("2026-08-27 19:00"), calendar: cal) == "Yesterday")
        #expect(MailFormatting.dayHeading(at("2026-08-24 09:00"),
                                          now: at("2026-08-27 19:00"), calendar: cal) == "Monday")
        #expect(MailFormatting.dayHeading(at("2026-08-03 09:00"),
                                          now: at("2026-08-27 19:00"), calendar: cal) == "3 Aug")
    }

    @Test func aRowStillShowsTheClock() {
        // The heading changed; the row's own time did not.
        let rows = TranscriptRows.build([msg("m0", at("2026-08-27 17:28"))],
                                        now: at("2026-08-27 19:00"), calendar: cal)
        #expect(rows[0].dayHeading == "Today")
        #expect(rows[0].time.contains("17"))
    }

    private func msg(_ id: String, _ date: Date) -> Message {
        Message(id: id, threadID: "t", sender: "a@b.com", recipients: [], subject: "s",
                date: date, bodyHTML: nil, bodyText: "b", isUnread: false, labelIDs: [])
    }
}
