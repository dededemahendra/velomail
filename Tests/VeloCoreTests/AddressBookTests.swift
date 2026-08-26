import Testing
import Foundation
@testable import VeloCore

@Suite struct AddressBookTests {
    private let me = "me@example.com"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() throws -> MailStore {
        MailStore(try AppDatabase.makeInMemory())
    }

    private func add(_ store: MailStore, id: String, from sender: String,
                     to recipients: [String] = [], cc: [String] = [],
                     daysAgo: Double = 0) throws {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        if try store.thread(id: "t-\(id)") == nil {
            try store.upsert(MailThread(id: "t-\(id)", sender: sender, snippet: "s",
                                        lastMessageDate: date, isUnread: false,
                                        hasAttachments: false, labelIDs: ["INBOX"]))
        }
        try store.upsert(Message(id: id, threadID: "t-\(id)", sender: sender,
                                 recipients: recipients, cc: cc, subject: "s", date: date,
                                 bodyHTML: nil, bodyText: "b", isUnread: false,
                                 labelIDs: ["INBOX"]))
    }

    private func book(_ store: MailStore) throws -> AddressBook {
        try AddressBook.build(from: store, identity: me, now: now)
    }

    // MARK: - What it knows

    @Test func anEmptyMailboxKnowsNobody() throws {
        #expect(try book(try makeStore()).suggestions(for: "a").isEmpty)
    }

    @Test func sendersBecomeContacts() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Natalie Roberts <natalie@sistercreatives.co>")

        let found = try book(store).suggestions(for: "nat")

        #expect(found.first?.address == "natalie@sistercreatives.co")
        #expect(found.first?.name == "Natalie Roberts")
    }

    @Test func recipientsAndCcAreLearnedToo() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "a@x.com", to: ["Bob <bob@x.com>"], cc: ["carol@x.com"])

        let book = try book(store)
        #expect(book.suggestions(for: "bob").first?.address == "bob@x.com")
        #expect(book.suggestions(for: "carol").first?.address == "carol@x.com")
    }

    @Test func yourOwnAddressIsNeverSuggested() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Me <ME@Example.com>", to: [me])

        // Suggesting yourself is never what you meant.
        #expect(try book(store).suggestions(for: "me").isEmpty)
    }

    @Test func theSameAddressIsOneContact() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Natalie <natalie@x.co>")
        try add(store, id: "m2", from: "natalie@x.co")
        try add(store, id: "m3", from: "Natalie Roberts <NATALIE@X.CO>")

        #expect(try book(store).suggestions(for: "natalie").count == 1)
    }

    @Test func theRichestNameWins() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "natalie@x.co")
        try add(store, id: "m2", from: "Natalie Roberts <natalie@x.co>")

        // A bare address seen once should not erase a name seen elsewhere.
        #expect(try book(store).suggestions(for: "natalie").first?.name == "Natalie Roberts")
    }

    // MARK: - Matching

    @Test func matchingWorksOnNameOrAddress() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Natalie Roberts <nr@sistercreatives.co>")

        #expect(try book(store).suggestions(for: "roberts").count == 1)
        #expect(try book(store).suggestions(for: "sistercreatives").count == 1)
    }

    @Test func matchingIsCaseInsensitive() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Natalie <natalie@x.co>")
        #expect(try book(store).suggestions(for: "NAT").count == 1)
    }

    @Test func anEmptyPrefixSuggestsNothing() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "a@x.com")
        // Otherwise opening the composer dumps the whole address book at you.
        #expect(try book(store).suggestions(for: "").isEmpty)
    }

    @Test func noMatchYieldsNothing() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "natalie@x.co")
        #expect(try book(store).suggestions(for: "zebra").isEmpty)
    }

    // MARK: - Ranking

    @Test func whoYouMailMostComesFirst() throws {
        let store = try makeStore()
        for i in 0..<5 { try add(store, id: "a\(i)", from: "Alice A <alice@x.co>", daysAgo: 40) }
        try add(store, id: "b1", from: "Alan B <alan@x.co>", daysAgo: 40)

        #expect(try book(store).suggestions(for: "al").first?.address == "alice@x.co")
    }

    @Test func aPrefixMatchBeatsAMatchInTheMiddle() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Zoe Nathanson <zoe@x.co>")
        try add(store, id: "m2", from: "Nat Green <nat@x.co>")

        // Typing "nat" almost always means the person called Nat.
        #expect(try book(store).suggestions(for: "nat").first?.address == "nat@x.co")
    }

    @Test func theListIsCapped() throws {
        let store = try makeStore()
        for i in 0..<40 { try add(store, id: "m\(i)", from: "Person \(i) <p\(i)@x.co>") }
        #expect(try book(store).suggestions(for: "p").count <= AddressBook.maximumSuggestions)
    }

    @Test func aDisplayLabelReadsAsAContact() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "Natalie Roberts <natalie@x.co>")

        let contact = try #require(try book(store).suggestions(for: "nat").first)
        #expect(contact.label == "Natalie Roberts <natalie@x.co>")
    }

    @Test func aContactWithoutANameLabelsAsItsAddress() throws {
        let store = try makeStore()
        try add(store, id: "m1", from: "bare@x.co")
        #expect(try book(store).suggestions(for: "bare").first?.label == "bare@x.co")
    }
}
