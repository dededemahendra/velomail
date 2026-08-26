import Testing
import Foundation
@testable import VeloCore

@Suite struct DraftStoreTests {
    private func makeStore() throws -> DraftStore {
        DraftStore(try AppDatabase.makeInMemory())
    }

    private func draft(subject: String = "Half written",
                       body: String = "I was saying",
                       threadID: String? = nil,
                       attachments: [DraftAttachment] = []) -> Draft {
        Draft(to: ["a@b.com"], cc: ["c@d.com"], subject: subject, bodyText: body,
              threadID: threadID, inReplyTo: threadID == nil ? nil : "<p@x.com>",
              references: threadID == nil ? [] : ["<p@x.com>"],
              attachments: attachments)
    }

    @Test func draftTableExists() throws {
        let db = try AppDatabase.makeInMemory()
        try db.dbQueue.read { db in
            let exists = try db.tableExists("draft")
            #expect(exists)
        }
    }

    @Test func nothingIsStoredInitially() throws {
        #expect(try makeStore().load() == nil)
    }

    @Test func aDraftRoundTrips() throws {
        let store = try makeStore()
        let original = draft()

        try store.save(original, at: Date(timeIntervalSince1970: 100))

        let restored = try #require(try store.load())
        #expect(restored.draft == original)
        #expect(restored.updatedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func savingAgainReplacesRatherThanAccumulating() throws {
        let store = try makeStore()
        try store.save(draft(subject: "first"), at: Date(timeIntervalSince1970: 1))
        try store.save(draft(subject: "second"), at: Date(timeIntervalSince1970: 2))

        // There is one draft slot, not a folder.
        #expect(try store.load()?.draft.subject == "second")
    }

    @Test func discardingClearsIt() throws {
        let store = try makeStore()
        try store.save(draft(), at: Date(timeIntervalSince1970: 1))

        try store.discard()

        #expect(try store.load() == nil)
    }

    @Test func discardingWhenEmptyIsHarmless() throws {
        try makeStore().discard()
    }

    @Test func aReplyDraftKeepsItsThread() throws {
        let store = try makeStore()
        try store.save(draft(threadID: "t1"), at: Date(timeIntervalSince1970: 1))

        let restored = try #require(try store.load()).draft

        // Losing this turns a resumed reply into a new message to the same
        // person, which is worse than losing the draft.
        #expect(restored.threadID == "t1")
        #expect(restored.inReplyTo == "<p@x.com>")
        #expect(restored.references == ["<p@x.com>"])
    }

    @Test func attachmentsSurviveWithTheDraft() throws {
        let store = try makeStore()
        let file = DraftAttachment(filename: "invoice.pdf", mimeType: "application/pdf",
                                   data: Data("PDF".utf8))
        try store.save(draft(attachments: [file]), at: Date(timeIntervalSince1970: 1))

        #expect(try store.load()?.draft.attachments == [file])
    }

    @Test func everyRecipientFieldSurvives() throws {
        let store = try makeStore()
        var original = draft()
        original.bcc = ["secret@example.com"]
        try store.save(original, at: Date(timeIntervalSince1970: 1))

        let restored = try #require(try store.load()).draft
        #expect(restored.to == ["a@b.com"])
        #expect(restored.cc == ["c@d.com"])
        #expect(restored.bcc == ["secret@example.com"])
    }

    @Test func anHTMLBodySurvives() throws {
        let store = try makeStore()
        var original = draft()
        original.bodyHTML = "<p>rich</p>"
        try store.save(original, at: Date(timeIntervalSince1970: 1))

        #expect(try store.load()?.draft.bodyHTML == "<p>rich</p>")
    }
}
