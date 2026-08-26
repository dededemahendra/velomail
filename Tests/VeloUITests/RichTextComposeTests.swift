import Testing
import Foundation
import VeloCore
@testable import VeloUI

/// What the composer puts on the wire when the writer used light markup.
@MainActor @Suite struct RichTextComposeTests {
    private func makeContext() throws -> (ComposeViewModel, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let outbound = OutboundService(writer: NoopWriter(), store: store,
                                       mutations: mutations, identity: "me@example.com")
        return (ComposeViewModel(outbound: outbound, identity: "me@example.com"), store, mutations)
    }

    /// A parent that carries HTML, so replies to it produce an HTML part.
    private func parent(in store: MailStore) throws -> Message {
        try store.upsert(MailThread(id: "t", sender: "Alice <alice@example.com>", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        let message = Message(id: "m", threadID: "t", sender: "Alice <alice@example.com>",
                              recipients: ["me@example.com"], subject: "Lunch",
                              date: Date(timeIntervalSince1970: 100),
                              bodyHTML: "<p>are you free?</p>", bodyText: "are you free?",
                              isUnread: false, labelIDs: ["INBOX"], messageIDHeader: "<p@x.com>")
        try store.upsert(message)
        return message
    }

    private func sent(_ model: ComposeViewModel,
                      _ mutations: MutationStore) throws -> QueuedBody.QueuedDraft {
        try model.send()
        return try JSONDecoder().decode(
            QueuedBody.self, from: try #require(try mutations.all().first).payload).draft
    }

    @Test func plainProseSendsNoHTMLPart() throws {
        let (model, _, mutations) = try makeContext()
        model.to = "you@example.com"
        model.subject = "Lunch"
        model.body = "One o'clock works."

        #expect(try sent(model, mutations).bodyHTML == nil)
    }

    @Test func marksBecomeAnHTMLPart() throws {
        let (model, _, mutations) = try makeContext()
        model.to = "you@example.com"
        model.subject = "Lunch"
        model.body = "**One** o'clock works."

        let draft = try sent(model, mutations)
        #expect(draft.bodyHTML?.contains("<strong>One</strong>") == true)
    }

    @Test func theTextPartKeepsWhatWasTyped() throws {
        // Clients that show the plain part get the marks, which is how everyone
        // already writes email. Stripping them would lose the emphasis entirely.
        let (model, _, mutations) = try makeContext()
        model.to = "you@example.com"
        model.subject = "Lunch"
        model.body = "**One** o'clock works."

        #expect(try sent(model, mutations).bodyText.contains("**One**"))
    }

    @Test func aFormattedReplyStillQuotesItsParent() throws {
        let (model, store, mutations) = try makeContext()
        model.startReply(to: try parent(in: store))
        model.body = "- yes\n- soon\n" + model.body

        let draft = try sent(model, mutations)
        #expect(draft.bodyHTML?.contains("<li>yes</li>") == true)
        #expect(draft.bodyHTML?.contains("blockquote") == true)
        #expect(draft.bodyText.contains("wrote:"))
    }

    @Test func theComposerSaysWhenItWillSendRichText() throws {
        // The writer should know the marks took, before the message is gone.
        let (model, _, _) = try makeContext()
        model.body = "plain"
        #expect(!model.isRichText)
        model.body = "**bold**"
        #expect(model.isRichText)
    }

    @Test func typedAngleBracketsAreNotMarkup() throws {
        let (model, _, mutations) = try makeContext()
        model.to = "you@example.com"
        model.subject = "Lunch"
        model.body = "**One** <b>not bold</b>"

        let html = try #require(try sent(model, mutations).bodyHTML)
        #expect(html.contains("&lt;b&gt;"))
        #expect(!html.contains("<b>"))
    }
}

/// Mirrors the parts of the queue payload this suite reads.
private struct QueuedBody: Decodable {
    struct QueuedDraft: Decodable {
        let bodyText: String
        let bodyHTML: String?
    }
    let draft: QueuedDraft
}

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError("unused") }
}
