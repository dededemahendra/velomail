import Testing
import Foundation
@testable import VeloCore

@Suite struct MailAnalyticsTests {
    private let me = "me@example.com"
    /// Thursday 27 August 2026, 17:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_787_850_000)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    /// Adds a message `hoursAgo` before `now`.
    private func add(_ store: MailStore, thread: String, id: String,
                     from sender: String, hoursAgo: Double) throws {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        if try store.thread(id: thread) == nil {
            try store.upsert(MailThread(id: thread, sender: sender, snippet: "s",
                                        lastMessageDate: date, isUnread: false,
                                        hasAttachments: false, labelIDs: ["INBOX"]))
        }
        try store.upsert(Message(id: id, threadID: thread, sender: sender, recipients: [me],
                                 subject: "s", date: date, bodyHTML: nil, bodyText: "b",
                                 isUnread: false, labelIDs: ["INBOX"]))
    }

    private func report(_ store: MailStore, days: Int = 7) throws -> MailAnalytics.Report {
        try MailAnalytics(store).report(identity: me, days: days, now: now, calendar: calendar)
    }

    // MARK: - Volume

    @Test func anEmptyMailboxReportsZeroes() throws {
        let report = try report(try makeStore())
        #expect(report.received == 0)
        #expect(report.sent == 0)
        #expect(report.medianResponse == nil)
    }

    @Test func receivedAndSentAreCountedSeparately() throws {
        let store = try makeStore()
        try add(store, thread: "t1", id: "a", from: "Alice <alice@x.com>", hoursAgo: 5)
        try add(store, thread: "t1", id: "b", from: "Me <me@example.com>", hoursAgo: 4)
        try add(store, thread: "t2", id: "c", from: "Bob <bob@x.com>", hoursAgo: 3)

        let report = try report(store)

        #expect(report.received == 2)
        #expect(report.sent == 1)
    }

    @Test func yourOwnAddressIsRecognisedThroughADisplayName() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "a", from: "Me Myself <ME@Example.com>", hoursAgo: 1)

        #expect(try report(store).sent == 1)
        #expect(try report(store).received == 0)
    }

    @Test func mailOutsideTheWindowIsExcluded() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "old", from: "alice@x.com", hoursAgo: 24 * 30)
        try add(store, thread: "t2", id: "new", from: "alice@x.com", hoursAgo: 2)

        #expect(try report(store, days: 7).received == 1)
    }

    // MARK: - Response time

    @Test func aReplyToAnInboundMessageCountsAsAResponse() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "in", from: "alice@x.com", hoursAgo: 10)
        try add(store, thread: "t", id: "out", from: me, hoursAgo: 8)

        #expect(try report(store).medianResponse == 2 * 3600)
    }

    @Test func theMedianIsTheMiddleOfSeveralResponses() throws {
        let store = try makeStore()
        for (index, gap) in [1.0, 5.0, 9.0].enumerated() {
            try add(store, thread: "t\(index)", id: "in\(index)", from: "alice@x.com", hoursAgo: 20)
            try add(store, thread: "t\(index)", id: "out\(index)", from: me, hoursAgo: 20 - gap)
        }

        // Median, not mean: one reply left for a week should not move the number
        // the way an average would.
        #expect(try report(store).medianResponse == 5 * 3600)
    }

    @Test func aThreadYouNeverRepliedToDoesNotCount() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "in", from: "alice@x.com", hoursAgo: 10)

        #expect(try report(store).medianResponse == nil)
    }

    @Test func yourOwnMessageFollowedByAnotherOfYoursIsOneResponse() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "in", from: "alice@x.com", hoursAgo: 10)
        try add(store, thread: "t", id: "out1", from: me, hoursAgo: 9)
        try add(store, thread: "t", id: "out2", from: me, hoursAgo: 8)

        // Following up on yourself is not a second response time.
        #expect(try report(store).medianResponse == 3600)
    }

    @Test func aThreadYouStartedIsNotAResponse() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "out", from: me, hoursAgo: 10)
        try add(store, thread: "t", id: "in", from: "alice@x.com", hoursAgo: 9)

        #expect(try report(store).medianResponse == nil)
    }

    // MARK: - Shape of the week

    @Test func dailyCountsCoverTheWholeWindowIncludingQuietDays() throws {
        let store = try makeStore()
        try add(store, thread: "t", id: "a", from: "alice@x.com", hoursAgo: 2)

        let report = try report(store, days: 7)

        // A gap in a chart has to be a zero, not a missing point.
        #expect(report.daily.count == 7)
        #expect(report.daily.map(\.received).reduce(0, +) == 1)
    }

    @Test func dailyCountsAreOldestFirst() throws {
        let report = try report(try makeStore(), days: 5)
        #expect(report.daily.first!.day < report.daily.last!.day)
    }

    @Test func theBusiestHourIsReported() throws {
        let store = try makeStore()
        // 17:00 now; three at 15:00, one at 09:00.
        for i in 0..<3 { try add(store, thread: "t\(i)", id: "a\(i)", from: "alice@x.com", hoursAgo: 2) }
        try add(store, thread: "tz", id: "z", from: "alice@x.com", hoursAgo: 8)

        #expect(try report(store).busiestHour == 15)
    }

    @Test func thereIsNoBusiestHourWithoutMail() throws {
        #expect(try report(try makeStore()).busiestHour == nil)
    }
}
