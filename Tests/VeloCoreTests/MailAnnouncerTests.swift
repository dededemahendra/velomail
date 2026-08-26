import Testing
import Foundation
@testable import VeloCore

private let identity = "me@example.com"

private func message(_ id: String, from sender: String = "Alice <alice@example.com>",
                     subject: String = "Lunch", ago: TimeInterval = 0,
                     unread: Bool = true, labels: [String] = ["INBOX"]) -> Message {
    Message(id: id, threadID: "t-\(id)", sender: sender, recipients: [identity],
            subject: subject, date: Date(timeIntervalSince1970: 1_000_000 - ago),
            bodyHTML: nil, bodyText: "the body", isUnread: unread,
            labelIDs: unread ? labels + ["UNREAD"] : labels)
}

@Suite struct MailAnnouncerTests {
    private let announcer = MailAnnouncer()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - The first run

    @Test func nothingIsAnnouncedWithoutABaseline() {
        let result = announcer.announce(messages: (0..<500).map { message("m\($0)", ago: TimeInterval($0)) },
                                        identity: identity, since: nil)
        // A fresh account backfills hundreds of messages. Five hundred banners
        // would be a first impression nobody forgives.
        #expect(result.items.isEmpty)
        #expect(result.additionalCount == 0)
    }

    @Test func theFirstRunStillRecordsTheMark() {
        let result = announcer.announce(messages: [message("m1")], identity: identity, since: nil)
        // Otherwise the *second* run announces everything instead.
        #expect(result.highWaterMark == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test func anEmptyMailboxLeavesTheMarkAlone() {
        let result = announcer.announce(messages: [], identity: identity, since: nil)
        #expect(result.highWaterMark == nil)
    }

    // MARK: - What counts

    @Test func newerUnreadMailIsAnnounced() {
        let result = announcer.announce(messages: [message("m1")], identity: identity,
                                        since: Date(timeIntervalSince1970: 999_000))
        #expect(result.items.count == 1)
        #expect(result.items.first?.title == "Alice")
        #expect(result.items.first?.subtitle == "Lunch")
    }

    @Test func mailOlderThanTheMarkIsNotAnnouncedAgain() {
        let result = announcer.announce(messages: [message("m1", ago: 5_000)], identity: identity,
                                        since: Date(timeIntervalSince1970: 999_000))
        #expect(result.items.isEmpty)
    }

    @Test func yourOwnMailIsNeverAnnounced() {
        let result = announcer.announce(messages: [message("m1", from: "Me <me@example.com>")],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        // Sending puts a message in the thread; it must not come back as
        // "new mail from you".
        #expect(result.items.isEmpty)
    }

    @Test func yourOwnMailIsRecognisedThroughADisplayName() {
        let result = announcer.announce(messages: [message("m1", from: "Me Myself <ME@Example.com>")],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        #expect(result.items.isEmpty)
    }

    @Test func readMailIsNotAnnounced() {
        let result = announcer.announce(messages: [message("m1", unread: false)],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        #expect(result.items.isEmpty)
    }

    @Test func mailOutsideTheInboxIsNotAnnounced() {
        let result = announcer.announce(messages: [message("m1", labels: ["SENT"])],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        #expect(result.items.isEmpty)
    }

    // MARK: - Not announcing twice

    @Test func theMarkAdvancesToTheNewestAnnounced() {
        let result = announcer.announce(messages: [message("m1", ago: 100), message("m2", ago: 0)],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        #expect(result.highWaterMark == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test func aRestartDoesNotReAnnounceTheInbox() {
        let inbox = [message("m1", ago: 100), message("m2", ago: 0)]
        let first = announcer.announce(messages: inbox, identity: identity,
                                       since: Date(timeIntervalSince1970: 1))
        #expect(first.items.count == 2)

        // Same mailbox, next launch, mark restored from disk.
        let second = announcer.announce(messages: inbox, identity: identity,
                                        since: first.highWaterMark)
        #expect(second.items.isEmpty)
    }

    @Test func theMarkNeverGoesBackwards() {
        let ahead = Date(timeIntervalSince1970: 2_000_000)
        let result = announcer.announce(messages: [message("m1")], identity: identity, since: ahead)
        #expect(result.highWaterMark == ahead)
    }

    // MARK: - Not interrupting twelve times

    @Test func aBurstIsCappedAndSummarised() {
        let burst = (0..<12).map { message("m\($0)", ago: TimeInterval($0)) }
        let result = announcer.announce(messages: burst, identity: identity,
                                        since: Date(timeIntervalSince1970: 1))

        #expect(result.items.count == MailAnnouncer.maximumBanners)
        #expect(result.additionalCount == 12 - MailAnnouncer.maximumBanners)
    }

    @Test func aSmallBatchHasNoSummary() {
        let result = announcer.announce(messages: [message("m1")], identity: identity,
                                        since: Date(timeIntervalSince1970: 1))
        #expect(result.additionalCount == 0)
    }

    @Test func theNewestAreTheOnesShown() {
        let burst = (0..<12).map { message("m\($0)", subject: "s\($0)", ago: TimeInterval($0) * 60) }
        let result = announcer.announce(messages: burst, identity: identity,
                                        since: Date(timeIntervalSince1970: 1))
        // If we can only show a few, show what just arrived.
        #expect(result.items.first?.subtitle == "s0")
    }

    // MARK: - Presentation

    @Test func aSenderWithoutADisplayNameShowsItsAddress() {
        let result = announcer.announce(messages: [message("m1", from: "bare@example.com")],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        #expect(result.items.first?.title == "bare@example.com")
    }

    @Test func anEmptySubjectStillReadsAsSomething() {
        let result = announcer.announce(messages: [message("m1", subject: "")],
                                        identity: identity, since: Date(timeIntervalSince1970: 1))
        #expect(result.items.first?.subtitle.isEmpty == false)
    }

    @Test func theAnnouncementCarriesItsThreadSoAClickCanOpenIt() {
        let result = announcer.announce(messages: [message("m1")], identity: identity,
                                        since: Date(timeIntervalSince1970: 1))
        #expect(result.items.first?.threadID == "t-m1")
    }
}
