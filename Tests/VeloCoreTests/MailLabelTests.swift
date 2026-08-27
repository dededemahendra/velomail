import Testing
import Foundation
@testable import VeloCore

@Suite struct MailLabelTests {
    private func makeStore() throws -> MailStore { MailStore(try AppDatabase.makeInMemory()) }

    private func seed(_ store: MailStore, id: String, labels: [String],
                      at seconds: TimeInterval = 10) throws {
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: seconds),
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
    }

    // MARK: - What a label is called

    @Test func aUserLabelKeepsTheNameItsOwnerGaveIt() {
        // The id is `Label_7`, which tells the reader nothing.
        let label = MailLabel(id: "Label_7", name: "Clients/Mornington", kind: .user)
        #expect(label.displayName == "Clients/Mornington")
    }

    @Test func aCategoryReadsAsAWord() {
        // Gmail ships these as CATEGORY_PROMOTIONS.
        #expect(MailLabel(id: "CATEGORY_PROMOTIONS", name: "CATEGORY_PROMOTIONS", kind: .system)
            .displayName == "Promotions")
        #expect(MailLabel(id: "CATEGORY_PERSONAL", name: "CATEGORY_PERSONAL", kind: .system)
            .displayName == "Personal")
    }

    @Test func theStructuralOnesAreNotLabelsToBrowse() {
        // INBOX, SENT and the rest already have views of their own; listing
        // them again as labels would be the same mail under two names.
        for id in ["INBOX", "SENT", "DRAFT", "TRASH", "SPAM", "UNREAD", "STARRED", "IMPORTANT"] {
            #expect(!MailLabel(id: id, name: id, kind: .system).isBrowsable, "\(id)")
        }
    }

    @Test func categoriesAndUserLabelsAreBrowsable() {
        #expect(MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system).isBrowsable)
        #expect(MailLabel(id: "Label_7", name: "Work", kind: .user).isBrowsable)
    }

    // MARK: - Storing them

    @Test func labelsRoundTrip() throws {
        let store = try makeStore()
        try store.replaceLabels([MailLabel(id: "Label_7", name: "Work", kind: .user)])

        #expect(try store.labels().map(\.name) == ["Work"])
    }

    @Test func aRenamedLabelIsNotADuplicate() throws {
        let store = try makeStore()
        try store.replaceLabels([MailLabel(id: "Label_7", name: "Work", kind: .user)])
        try store.replaceLabels([MailLabel(id: "Label_7", name: "Clients", kind: .user)])

        #expect(try store.labels().map(\.name) == ["Clients"])
    }

    @Test func aDeletedLabelStopsBeingListed() throws {
        // The list is replaced wholesale because Gmail's answer is the truth.
        let store = try makeStore()
        try store.replaceLabels([MailLabel(id: "Label_7", name: "Work", kind: .user),
                                 MailLabel(id: "Label_8", name: "Gone", kind: .user)])
        try store.replaceLabels([MailLabel(id: "Label_7", name: "Work", kind: .user)])

        #expect(try store.labels().map(\.id) == ["Label_7"])
    }

    @Test func browsableOnesComeBackInReadingOrder() throws {
        // Categories first, then a person's own labels alphabetically: the ones
        // Gmail made are a fixed set and belong together.
        let store = try makeStore()
        try store.replaceLabels([
            MailLabel(id: "Label_9", name: "Zebra", kind: .user),
            MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system),
            MailLabel(id: "Label_1", name: "Alpha", kind: .user),
            MailLabel(id: "INBOX", name: "INBOX", kind: .system),
        ])

        #expect(try store.browsableLabels().map(\.displayName) == ["Updates", "Alpha", "Zebra"])
    }

    // MARK: - Mail under a label

    @Test func threadsCanBeListedByLabel() throws {
        let store = try makeStore()
        try seed(store, id: "work", labels: ["INBOX", "Label_7"])
        try seed(store, id: "other", labels: ["INBOX"])

        #expect(try store.threads(withLabel: "Label_7").map(\.id) == ["work"])
    }

    @Test func aLabelIsNotMatchedByAPrefixOfAnother() throws {
        // Label_7 must not pull in Label_70.
        let store = try makeStore()
        try seed(store, id: "seventy", labels: ["Label_70"])

        #expect(try store.threads(withLabel: "Label_7").isEmpty)
    }

    @Test func theNewestComesFirst() throws {
        let store = try makeStore()
        try seed(store, id: "old", labels: ["Label_7"], at: 10)
        try seed(store, id: "new", labels: ["Label_7"], at: 30)

        #expect(try store.threads(withLabel: "Label_7").map(\.id) == ["new", "old"])
    }
}
