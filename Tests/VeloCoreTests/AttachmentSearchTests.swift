import Testing
import Foundation
@testable import VeloCore

@Suite struct AttachmentSearchTests {
    private func makeContext() throws -> (SearchService, MailStore) {
        let db = try AppDatabase.makeInMemory()
        return (SearchService(db), MailStore(db))
    }

    private func seed(_ store: MailStore, thread: String = "t", message: String = "m",
                      subject: String = "Here it is", body: String = "see attached",
                      files: [String] = []) throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try store.upsert(MailThread(id: thread, sender: "a@b.com", snippet: body,
                                    lastMessageDate: date, isUnread: false,
                                    hasAttachments: !files.isEmpty, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: message, threadID: thread, sender: "a@b.com",
                                 recipients: [], subject: subject, date: date,
                                 bodyHTML: nil, bodyText: body, isUnread: false,
                                 labelIDs: ["INBOX"]))
        for (index, name) in files.enumerated() {
            try store.upsert(MailAttachment(id: "\(message):\(index)", messageID: message,
                                            filename: name, mimeType: "application/pdf",
                                            size: 10, attachmentID: "a", inlineData: nil))
        }
    }

    @Test func aThreadIsFoundByItsAttachmentName() throws {
        let (search, store) = try makeContext()
        try seed(store, files: ["mornington-invoice.pdf"])

        // The whole point of attaching a file is that you go looking for it later.
        #expect(try search.search(SearchQuery(terms: "mornington")).map(\.id) == ["t"])
    }

    @Test func theExtensionIsSearchable() throws {
        let (search, store) = try makeContext()
        try seed(store, files: ["report.xlsx"])
        #expect(try search.search(SearchQuery(terms: "xlsx")).map(\.id) == ["t"])
    }

    @Test func hyphenatedNamesMatchTheirParts() throws {
        let (search, store) = try makeContext()
        try seed(store, files: ["eastern-boundary-survey.pdf"])
        #expect(try search.search(SearchQuery(terms: "boundary")).map(\.id) == ["t"])
    }

    @Test func aThreadWithoutThatFileIsNotFound() throws {
        let (search, store) = try makeContext()
        try seed(store, files: ["invoice.pdf"])
        #expect(try search.search(SearchQuery(terms: "spreadsheet")).isEmpty)
    }

    @Test func aThreadAppearsOnceEvenWithSeveralMatchingFiles() throws {
        let (search, store) = try makeContext()
        try seed(store, files: ["survey-one.pdf", "survey-two.pdf"])
        #expect(try search.search(SearchQuery(terms: "survey")).map(\.id) == ["t"])
    }

    @Test func removingAnAttachmentRemovesItFromTheIndex() throws {
        let (search, store) = try makeContext()
        try seed(store, files: ["invoice.pdf"])
        try store.deleteMessage(id: "m")

        #expect(try search.search(SearchQuery(terms: "invoice")).isEmpty)
    }

    @Test func bodyAndSubjectSearchStillWork() throws {
        let (search, store) = try makeContext()
        try seed(store, subject: "Quarterly report", body: "numbers inside", files: ["x.pdf"])

        #expect(try search.search(SearchQuery(terms: "quarterly")).map(\.id) == ["t"])
        #expect(try search.search(SearchQuery(terms: "numbers")).map(\.id) == ["t"])
    }

    @Test func existingAttachmentsAreBackfilledIntoTheIndex() throws {
        // The migration must index what is already stored, or attachment search
        // silently returns nothing for every file received before the upgrade.
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try seed(store, files: ["already-here.pdf"])

        let rows = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT count(*) FROM attachmentSearch") ?? 0
        }
        #expect(rows == 1)
    }
}
