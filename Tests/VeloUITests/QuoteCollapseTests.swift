import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct QuoteCollapseTests {
    private func makeContext() throws -> (ComposeViewModel, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let model = ComposeViewModel(
            outbound: OutboundService(writer: Quiet(), store: store, mutations: mutations,
                                      identity: "me@x.com"),
            identity: "me@x.com", drafts: DraftStore(db),
            parentLookup: { threadID in try? store.messages(inThread: threadID).last })
        return (model, store, mutations)
    }

    /// A parent like the ones that made this necessary: a newsletter whose
    /// plain-text half is mostly tracking URLs.
    @discardableResult
    private func parent(in store: MailStore) throws -> Message {
        let noisy = (1...20)
            .map { "Line \($0) (https://info.example.com/e3t/Ctc/OT+113/\($0)/aVeryLongTrackingToken)" }
            .joined(separator: "\n\n")
        try store.upsert(MailThread(id: "t", sender: "Team <hello@x.com>", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        let message = Message(id: "m", threadID: "t", sender: "Team <hello@x.com>",
                              recipients: ["me@x.com"], subject: "Aperture",
                              date: Date(timeIntervalSince1970: 100),
                              bodyHTML: "<p>Aperture is GA</p>", bodyText: noisy,
                              isUnread: false, labelIDs: ["INBOX"], messageIDHeader: "<p@x.com>")
        try store.upsert(message)
        return message
    }

    private func sent(_ model: ComposeViewModel, _ mutations: MutationStore) throws -> QuotedDraft {
        try model.send()
        return try JSONDecoder().decode(
            QueuedQuote.self, from: try #require(try mutations.all().first).payload).draft
    }

    // MARK: - What the writer sees

    @Test func replyingLeavesTheEditorClean() throws {
        // The wall of quoted text was the complaint: you scrolled past twenty
        // lines of someone else's tracking URLs to reach your own cursor.
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))

        #expect(!model.body.contains("wrote:"))
        #expect(!model.body.contains("info.example.com"))
        #expect(model.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func theQuoteIsStillThereJustNotInTheWay() throws {
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))

        #expect(model.quotedSummary == "Team, 1 Jan 1970")
        #expect(model.includesQuote)
    }

    @Test func aNewMessageQuotesNothing() throws {
        let (model, _, _) = try makeContext()
        model.startNew()
        #expect(model.quotedSummary == nil)
    }

    // MARK: - What actually goes out

    @Test func theQuoteIsAttachedAtSendTime() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Yes, that works."

        let draft = try sent(model, mutations)

        #expect(draft.bodyText.hasPrefix("Yes, that works."))
        #expect(draft.bodyText.contains("wrote:"))
        #expect(draft.bodyText.contains("> Line 1"))
    }

    @Test func theHTMLQuoteIsTheParentsOwnMarkupNotAReTypedCopy() throws {
        // The whole reason to attach at send time: QuotedReply.html can use the
        // parent's real HTML, where deriving a blockquote from "> " lines gave
        // a plain-text rendition of a message that had better to offer.
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Yes."

        let draft = try sent(model, mutations)

        #expect(draft.bodyHTML?.contains("<p>Aperture is GA</p>") == true)
        #expect(draft.bodyHTML?.contains("blockquote") == true)
    }

    @Test func theQuoteCanBeDropped() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Yes."
        model.includesQuote = false

        let draft = try sent(model, mutations)

        #expect(!draft.bodyText.contains("wrote:"))
        #expect(draft.bodyHTML?.contains("blockquote") != true)
    }

    @Test func aReplyIsStillQuotedExactlyOnce() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Yes."

        let draft = try sent(model, mutations)

        #expect(draft.bodyText.components(separatedBy: "wrote:").count - 1 == 1)
    }

    // MARK: - Leaving and coming back

    @Test func aResumedReplyStillKnowsWhatItIsAnsweringed() throws {
        // Without the parent, resuming would send a reply with no quote and no
        // sign that one was ever meant to be there.
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Half an answer"
        model.autosave()

        model.startNew()
        model.resumeDraft()

        #expect(model.body == "Half an answer")
        #expect(model.quotedSummary != nil)
    }

    @Test func aResumedReplyStillQuotesWhenSent() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Half an answer"
        model.autosave()
        model.startNew()
        model.resumeDraft()

        let draft = try sent(model, mutations)

        #expect(draft.bodyText.contains("wrote:"))
    }

    @Test func whatIsStoredIsWhatWasTypedNotTheQuote() throws {
        // Otherwise every autosave grows by the size of the parent message.
        let (model, store, _) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "Half an answer"
        model.autosave()

        #expect(model.storedDrafts.first?.draft.bodyText == "Half an answer")
    }
}

private struct QueuedQuote: Decodable {
    let draft: QuotedDraft
}

struct QuotedDraft: Decodable {
    let bodyText: String
    let bodyHTML: String?
}
