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

@Suite struct ThreadChipTests {
    private let known = (0..<7).map { MailLabel(id: "L\($0)", name: "Name \($0)", kind: .user) }
    private var allIDs: [String] { ["INBOX"] + known.map(\.id) }

    @Test func aHeaderDrawsOnlyWhatItHasRoomFor() {
        // Seven chips squashed until the words wrapped inside their own
        // capsules, and pushed the message count off the row entirely.
        let chips = ThreadDetail.chips(on: allIDs, known: known)
        #expect(chips.shown.count == 3)
        #expect(chips.extra == 4)
    }

    @Test func aFewLabelsAreAllShownWithNoCount() {
        let chips = ThreadDetail.chips(on: ["INBOX", "L0", "L1"], known: known)
        #expect(chips.shown.count == 2)
        #expect(chips.extra == 0)
    }

    @Test func exactlyTheLimitIsNotOverflowed() {
        // An off-by-one here would render "Name 0 Name 1 Name 2 +0".
        let chips = ThreadDetail.chips(on: ["L0", "L1", "L2"], known: known)
        #expect(chips.shown.count == 3)
        #expect(chips.extra == 0)
    }

    @Test func theHiddenOnesAreTheLaterOnesInSidebarOrder() {
        let chips = ThreadDetail.chips(on: allIDs, known: known, limit: 2)
        #expect(chips.shown.map(\.displayName) == ["Name 0", "Name 1"])
        #expect(chips.extra == 5)
    }
}
