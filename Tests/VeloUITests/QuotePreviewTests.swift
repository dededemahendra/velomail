import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct QuotePreviewTests {
    private func makeModel() throws -> (ComposeViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let model = ComposeViewModel(
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com")
        return (model, store)
    }

    @discardableResult
    private func parent(in store: MailStore, html: String?) throws -> Message {
        try store.upsert(MailThread(id: "t", sender: "Team <hello@x.com>", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        let message = Message(id: "m", threadID: "t", sender: "Team <hello@x.com>",
                              recipients: ["me@x.com"], subject: "s",
                              date: Date(timeIntervalSince1970: 100),
                              bodyHTML: html, bodyText: "plain words",
                              isUnread: false, labelIDs: ["INBOX"], messageIDHeader: "<p@x.com>")
        try store.upsert(message)
        return message
    }

    // MARK: - What the expander gets

    @Test func theExpanderGetsTheMessageItself() throws {
        // Not a re-typed copy: the same view the thread pane uses, so the quote
        // looks like the mail it came from.
        let (model, store) = try makeModel()
        let message = try parent(in: store, html: "<p>Rendered</p>")
        model.startReply(to: message)

        #expect(model.quotedMessage?.id == "m")
    }

    @Test func thereIsNothingToShowForANewMessage() throws {
        let (model, _) = try makeModel()
        model.startNew()
        #expect(model.quotedMessage == nil)
    }

    // MARK: - Not fetching anything while you write

    @Test func aQuotePreviewNeverLoadsRemoteImages() throws {
        // A tracking pixel in the quote would fire while the reply is being
        // written, telling the sender the message was opened when it was not
        // even read. The reader's standing preference is about mail they are
        // reading, not mail they are answering.
        #expect(!MessageBodyView.previewOfQuote(Fixture.message).loadsRemoteImages)
    }

    @Test func theQuotePreviewStillShowsPicturesTheMessageBrought() throws {
        // Inline parts carry their own bytes and fetch nothing.
        let view = MessageBodyView.previewOfQuote(Fixture.message, attachments: [Fixture.inline])
        #expect(view.attachments.count == 1)
    }
}

private enum Fixture {
    static let message = Message(
        id: "m", threadID: "t", sender: "a@b.com", recipients: [], subject: "s",
        date: Date(timeIntervalSince1970: 1), bodyHTML: "<p>hi</p>", bodyText: nil,
        isUnread: false, labelIDs: [])

    static let inline = MailAttachment(
        id: "a", messageID: "m", filename: "logo.png", mimeType: "image/png",
        size: 3, attachmentID: nil, inlineData: "AAA", contentID: "logo@x")
}
