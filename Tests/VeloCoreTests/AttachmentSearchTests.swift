import Testing
import Foundation
@testable import VeloCore

/// Attachments have been searchable by filename since migration v15 -- free
/// text already matches `attachmentSearch`. What there was no way to say is
/// "only threads that have a file" or "a file called this and never mind the
/// message body", which is how people actually go looking for a document they
/// know they were sent.
@Suite struct AttachmentSearchTests {
    // MARK: - Parsing

    @Test func hasAttachmentIsRecognised() {
        #expect(SearchQuery.parse("has:attachment").hasAttachment == true)
        #expect(SearchQuery.parse("invoice has:attachment").terms == "invoice")
    }

    @Test func gmailsPluralSpellingWorksToo() {
        // Gmail accepts `has:attachment`; enough people type the plural that
        // rejecting it would just look broken.
        #expect(SearchQuery.parse("has:attachments").hasAttachment == true)
    }

    @Test func hasSomethingElseIsLeftAsWords() {
        // Not silently swallowed: searching for what was typed beats dropping it.
        let query = SearchQuery.parse("has:wings")
        #expect(query.hasAttachment == nil)
        #expect(query.terms == "has:wings")
    }

    @Test func filenameIsRecognisedAndQuotable() {
        #expect(SearchQuery.parse("filename:invoice.pdf").filename == "invoice.pdf")
        #expect(SearchQuery.parse("filename:\"end of year.pdf\"").filename == "end of year.pdf")
    }

    @Test func aFilenameDoesNotAlsoBecomeFreeText() {
        let query = SearchQuery.parse("filename:report.pdf quarterly")
        #expect(query.filename == "report.pdf")
        #expect(query.terms == "quarterly")
    }

    @Test func bothCountAsOperatorsAndAsNonEmpty() {
        #expect(SearchQuery.parse("has:attachment").hasOperators)
        #expect(!SearchQuery.parse("has:attachment").isEmpty)
        #expect(SearchQuery.parse("filename:x.pdf").hasOperators)
        #expect(!SearchQuery.parse("filename:x.pdf").isEmpty)
    }

    @Test func bothAreShownBackToThePersonWhoTypedThem() {
        // Otherwise there is no telling whether it filtered or searched for the
        // literal string, and an empty result looks identical either way.
        #expect(SearchQuery.parse("has:attachment").filterLabels().contains("Has a file"))
        #expect(SearchQuery.parse("filename:invoice.pdf").filterLabels()
                    .contains("File named invoice.pdf"))
    }

    // MARK: - Searching

    private func store() throws -> (MailStore, SearchService) {
        let database = try AppDatabase.makeInMemory()
        return (MailStore(database), SearchService(database))
    }

    private func message(_ id: String, thread: String, subject: String,
                         hasAttachments: Bool) -> Message {
        Message(id: id, threadID: thread, sender: "alice@example.com",
                recipients: ["me@example.com"], subject: subject,
                date: Date(timeIntervalSince1970: 100), bodyHTML: nil, bodyText: "body",
                isUnread: false, labelIDs: ["INBOX"])
    }

    private func seed(_ store: MailStore) throws {
        for (id, subject, hasFile) in [("t1", "Quarterly report", true),
                                       ("t2", "Quarterly chat", false)] {
            try store.upsert(MailThread(id: id, sender: "alice@example.com", snippet: subject,
                                        lastMessageDate: Date(timeIntervalSince1970: 100),
                                        isUnread: false, hasAttachments: hasFile,
                                        labelIDs: ["INBOX"]))
            try store.upsert(message("m\(id)", thread: id, subject: subject,
                                     hasAttachments: hasFile))
        }
        try store.upsert(MailAttachment(id: "mt1-1", messageID: "mt1",
                                        filename: "invoice.pdf",
                                        mimeType: "application/pdf", size: 10,
                                        attachmentID: "a1", inlineData: nil))
    }

    @Test func hasAttachmentKeepsOnlyThreadsCarryingAFile() throws {
        let (store, search) = try store()
        try seed(store)

        let all = try search.search(SearchQuery.parse("quarterly"))
        #expect(all.count == 2)

        let withFiles = try search.search(SearchQuery.parse("quarterly has:attachment"))
        #expect(withFiles.map(\.id) == ["t1"])
    }

    @Test func filenameFindsAThreadByItsFileAlone() throws {
        let (store, search) = try store()
        try seed(store)

        // No word of "invoice" appears in either subject or body.
        let found = try search.search(SearchQuery.parse("filename:invoice"))
        #expect(found.map(\.id) == ["t1"])
    }

    @Test func aFilenameThatMatchesNothingFindsNothing() throws {
        let (store, search) = try store()
        try seed(store)

        #expect(try search.search(SearchQuery.parse("filename:receipt")).isEmpty)
    }

    /// The filter has to be the thread's own flag, not "some message here has a
    /// row in the attachment table" -- attachments are fetched on demand, so a
    /// thread can be known to carry a file long before any row exists for it.
    @Test func hasAttachmentDoesNotWaitForAttachmentRowsToBeFetched() throws {
        let (store, search) = try store()
        try store.upsert(MailThread(id: "t9", sender: "alice@example.com", snippet: "deck",
                                    lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: false, hasAttachments: true, labelIDs: ["INBOX"]))
        try store.upsert(message("m9", thread: "t9", subject: "deck", hasAttachments: true))

        #expect(try search.search(SearchQuery.parse("deck has:attachment")).map(\.id) == ["t9"])
    }
}
