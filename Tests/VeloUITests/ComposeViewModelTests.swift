import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct ComposeViewModelTests {
    private func makeContext() throws -> (ComposeViewModel, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let outbound = OutboundService(writer: NoopWriter(), store: store,
                                       mutations: mutations, identity: "me@example.com")
        return (ComposeViewModel(outbound: outbound, identity: "me@example.com"), store, mutations)
    }

    private func parent(in store: MailStore) throws -> Message {
        try store.upsert(MailThread(id: "t", sender: "Alice <alice@example.com>", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        let message = Message(id: "m", threadID: "t", sender: "Alice <alice@example.com>",
                              recipients: ["me@example.com"], subject: "Lunch",
                              date: Date(timeIntervalSince1970: 100),
                              bodyHTML: nil, bodyText: "are you free?", isUnread: false,
                              labelIDs: ["INBOX"], messageIDHeader: "<p@x.com>")
        try store.upsert(message)
        return message
    }

    @Test func newComposeStartsEmpty() throws {
        let (model, _, _) = try makeContext()
        model.startNew()
        #expect(model.to.isEmpty)
        #expect(model.subject.isEmpty)
        #expect(model.body.isEmpty)
        #expect(!model.isReply)
    }

    @Test func cannotSendWithoutARecipient() throws {
        let (model, _, _) = try makeContext()
        model.startNew()
        model.subject = "hi"
        #expect(!model.canSend)
        model.to = "a@b.com"
        #expect(model.canSend)
    }

    @Test func whitespaceOnlyRecipientDoesNotCount() throws {
        let (model, _, _) = try makeContext()
        model.startNew()
        model.to = "  ,  "
        #expect(!model.canSend)
    }

    @Test func sendEnqueuesADraftAndClears() throws {
        let (model, _, mutations) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        model.subject = "Hello"
        model.body = "hi there"

        try model.send()

        // Queued, but deliberately not yet due -- that gap is the undo window.
        #expect(try mutations.all().count == 1)
        #expect(try mutations.all().first?.kind == .send)
        #expect(try mutations.pending().isEmpty)
        #expect(model.to.isEmpty)          // cleared, ready for the next one
    }

    @Test func replySeedsRecipientAndSubjectFromTheMessage() throws {
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))

        #expect(model.to == "Alice <alice@example.com>")
        #expect(model.subject == "Re: Lunch")
        #expect(model.isReply)
    }

    @Test func replySeedsTheQuotedParentIntoTheEditor() throws {
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))

        // What is in the editor is what gets sent, so the quote has to be
        // visible and editable rather than bolted on at send time.
        #expect(model.body.contains("wrote:"))
        #expect(model.body.contains("> are you free?"))
    }

    @Test func replyLeavesRoomToTypeAboveTheQuote() throws {
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))
        #expect(model.body.hasPrefix("\n\n"))
    }

    @Test func sendingAReplyDoesNotQuoteTwice() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Yes.\n\n" + model.body

        try model.send()

        let queued = try JSONDecoder().decode(
            QueuedSend.self, from: try #require(try mutations.all().first).payload)
        let occurrences = queued.draft.bodyText.components(separatedBy: "wrote:").count - 1
        #expect(occurrences == 1)
    }

    @Test func startingANewComposeClearsReplyContext() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.startNew()
        model.to = "fresh@example.com"
        model.subject = "Fresh"
        model.body = "no quote"

        try model.send()

        let queued = try JSONDecoder().decode(
            QueuedSend.self, from: try #require(try mutations.all().first).payload)
        #expect(queued.draft.threadID == nil)       // a new thread, not the reply's
        #expect(!queued.draft.bodyText.contains("wrote:"))
    }
}

/// Mirrors the queue payload's shape. A local decoder keeps OutboundSendPayload
/// internal to VeloCore rather than widening its API for a test.
private struct QueuedSend: Decodable {
    struct QueuedDraft: Decodable {
        let bodyText: String
        let threadID: String?
    }
    let draft: QueuedDraft
}

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError("unused") }
}
