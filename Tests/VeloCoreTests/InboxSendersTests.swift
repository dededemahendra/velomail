import Testing
import Foundation
@testable import VeloCore

@Suite struct InboxSendersTests {
    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    private func add(_ store: MailStore, id: String, sender: String,
                     labels: [String] = ["INBOX"], unread: Bool = false,
                     unsubscribe: String? = nil, day: Int = 0,
                     snoozed: Date? = nil) throws {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        try store.upsert(MailThread(id: id, sender: sender, snippet: "s",
                                    lastMessageDate: date, isUnread: unread,
                                    hasAttachments: false, labelIDs: labels,
                                    snoozedUntil: snoozed))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: sender,
                                 recipients: ["me@x.com"], subject: "s", date: date,
                                 bodyHTML: nil, bodyText: "b", isUnread: unread,
                                 labelIDs: labels, listUnsubscribe: unsubscribe))
    }

    @Test func itSaysWhoIsFillingTheInbox() throws {
        let store = try makeStore()
        for i in 0..<9 { try add(store, id: "loud\(i)", sender: "Xero <billing@xero.com>") }
        try add(store, id: "q", sender: "Peta <peta@example.com>")

        let senders = try store.inboxSenders()
        #expect(senders.first?.address == "billing@xero.com")
        #expect(senders.first?.threads == 9)
        #expect(senders.count == 2)
    }

    @Test func archivedMailIsNotSomeoneStillFillingYourInbox() throws {
        let store = try makeStore()
        try add(store, id: "in", sender: "a@x.com")
        try add(store, id: "out", sender: "a@x.com", labels: ["ARCHIVE"])

        #expect(try store.inboxSenders().first?.threads == 1)
    }

    @Test func aSnoozedThreadIsNotInTheInboxYet() throws {
        let store = try makeStore()
        let later = Date(timeIntervalSince1970: 90_000)
        try add(store, id: "sleeping", sender: "a@x.com", snoozed: later)

        #expect(try store.inboxSenders(now: Date(timeIntervalSince1970: 1)).isEmpty)
        #expect(try store.inboxSenders(now: Date(timeIntervalSince1970: 100_000)).count == 1)
    }

    @Test func oneUnsubscribableMessageIsEnough() throws {
        // The header is per message and bulk senders do not always set it.
        let store = try makeStore()
        try add(store, id: "a", sender: "list@x.com")
        try add(store, id: "b", sender: "list@x.com", unsubscribe: "<mailto:off@x.com>")

        #expect(try store.inboxSenders().first?.canUnsubscribe == true)
    }

    @Test func aSenderWithNoUnsubscribeAnywhereIsNotOfferedOne() throws {
        // A button that does nothing when pressed is worse than no button.
        let store = try makeStore()
        try add(store, id: "a", sender: "person@x.com")

        #expect(try store.inboxSenders().first?.canUnsubscribe == false)
    }

    @Test func unreadIsCounted() throws {
        let store = try makeStore()
        try add(store, id: "a", sender: "a@x.com", unread: true)
        try add(store, id: "b", sender: "a@x.com", unread: true)
        try add(store, id: "c", sender: "a@x.com")

        #expect(try store.inboxSenders().first?.unread == 2)
    }

    // MARK: - Acting on one

    @Test func everythingFromOneAddressCanBeFound() throws {
        let store = try makeStore()
        for i in 0..<4 { try add(store, id: "x\(i)", sender: "Xero <billing@xero.com>", day: i) }
        try add(store, id: "other", sender: "peta@example.com")

        let theirs = try store.inboxThreads(from: "billing@xero.com")
        #expect(theirs.count == 4)
        #expect(theirs.allSatisfy { $0.id.hasPrefix("x") })
    }

    @Test func theNameOnTheHeaderDoesNotChangeWhoTheyAre() throws {
        let store = try makeStore()
        try add(store, id: "a", sender: "Xero <billing@xero.com>")
        try add(store, id: "b", sender: "Xero Invoices <BILLING@xero.com>")

        #expect(try store.inboxThreads(from: "Anything <billing@XERO.com>").count == 2)
    }

    @Test func anEmptyInboxHasNoSenders() throws {
        #expect(try makeStore().inboxSenders().isEmpty)
    }
}
