import Testing
import Foundation
@testable import VeloCore

@Suite struct FollowUpServiceTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let identity = "me@example.com"

    private func makeContext() throws -> (FollowUpService, MailStore) {
        let db = try AppDatabase.makeInMemory()
        return (FollowUpService(MailStore(db)), MailStore(db))
    }

    /// Seeds a thread whose messages are given as (sender, secondsAgo).
    private func seed(_ store: MailStore, id: String,
                      messages: [(sender: String, ago: TimeInterval)]) throws {
        let newest = messages.map { now.addingTimeInterval(-$0.ago) }.max()!
        try store.upsert(MailThread(id: id, sender: messages.last!.sender, snippet: "s",
                                    lastMessageDate: newest, isUnread: false,
                                    hasAttachments: false, labelIDs: ["SENT"]))
        for (index, message) in messages.enumerated() {
            try store.upsert(Message(id: "\(id)-m\(index)", threadID: id, sender: message.sender,
                                     recipients: ["them@example.com"], subject: "s",
                                     date: now.addingTimeInterval(-message.ago),
                                     bodyHTML: nil, bodyText: "b", isUnread: false,
                                     labelIDs: ["SENT"]))
        }
    }

    private let threeDays: TimeInterval = 3 * 86_400

    @Test func aThreadYouSpokeLastInAndHeardNothingBackNeedsFollowUp() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t", messages: [("them@example.com", 10 * 86_400),
                                            (identity, 5 * 86_400)])

        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now)
                    .map(\.id) == ["t"])
    }

    @Test func aThreadTheyRepliedToDoesNotNeedFollowUp() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t", messages: [(identity, 10 * 86_400),
                                            ("them@example.com", 5 * 86_400)])

        // Derived, not flagged: the moment a reply lands it stops appearing,
        // with nothing having to notice and clear a flag.
        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now).isEmpty)
    }

    @Test func aRecentlySentThreadIsNotYetOverdue() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t", messages: [(identity, 3_600)])

        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now).isEmpty)
    }

    @Test func theWindowIsRespected() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t", messages: [(identity, 2 * 86_400)])

        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now).isEmpty)
        #expect(try service.awaitingReply(identity: identity, after: 86_400, now: now)
                    .map(\.id) == ["t"])
    }

    @Test func identityMatchingIgnoresDisplayNamesAndCase() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "t", messages: [("Me Myself <ME@Example.com>", 5 * 86_400)])

        // Headers routinely arrive as "Display Name <addr>".
        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now)
                    .map(\.id) == ["t"])
    }

    @Test func oldestOverdueComesFirstSoTheStalestIsChasedFirst() throws {
        let (service, store) = try makeContext()
        try seed(store, id: "recent", messages: [(identity, 4 * 86_400)])
        try seed(store, id: "ancient", messages: [(identity, 20 * 86_400)])

        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now)
                    .map(\.id) == ["ancient", "recent"])
    }

    @Test func anEmptyMailboxNeedsNoFollowUp() throws {
        let (service, _) = try makeContext()
        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now).isEmpty)
    }

    @Test func aThreadWithNoMessagesIsIgnored() throws {
        let (service, store) = try makeContext()
        try store.upsert(MailThread(id: "empty", sender: identity, snippet: "s",
                                    lastMessageDate: now.addingTimeInterval(-10 * 86_400),
                                    isUnread: false, hasAttachments: false, labelIDs: ["SENT"]))

        #expect(try service.awaitingReply(identity: identity, after: threeDays, now: now).isEmpty)
    }
}
