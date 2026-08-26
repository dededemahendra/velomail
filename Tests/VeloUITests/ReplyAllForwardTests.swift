import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct ReplyAllForwardTests {
    private let me = "me@x.com"

    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let date = Date(timeIntervalSince1970: 1_000)
        try store.upsert(MailThread(id: "t", sender: "Alice <alice@x.com>", snippet: "s",
                                    lastMessageDate: date, isUnread: false,
                                    hasAttachments: true, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m", threadID: "t", sender: "Alice <alice@x.com>",
                                 recipients: [me, "Bob <bob@x.com>"], cc: ["carol@x.com"],
                                 subject: "Invoice", date: date, bodyHTML: nil,
                                 bodyText: "attached", isUnread: false, labelIDs: ["INBOX"],
                                 messageIDHeader: "<orig@x.com>"))
        try store.upsert(MailAttachment(id: "m:0", messageID: "m", filename: "invoice.pdf",
                                        mimeType: "application/pdf", size: 3,
                                        attachmentID: nil,
                                        inlineData: Data("PDF".utf8).base64EncodedString()))
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: me),
            identity: me, isSignedIn: true)
        try app.start()
        return (app, store)
    }

    // MARK: - Reply all

    @Test func shiftRRepliesToEveryone() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("r"), [.shift]))

        #expect(app.route == .compose)
        #expect(app.compose.to == "Alice <alice@x.com>")
        // Everyone else on it, minus you.
        #expect(app.compose.cc.contains("Bob"))
        #expect(app.compose.cc.contains("carol@x.com"))
        #expect(!app.compose.cc.contains(me))
    }

    @Test func plainReplyStillGoesOnlyToTheSender() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("r")))

        #expect(app.compose.to == "Alice <alice@x.com>")
        #expect(app.compose.cc.isEmpty)
    }

    @Test func aReplyAllIsStillThreaded() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("r"), [.shift]))
        #expect(app.compose.isReply)
    }

    // MARK: - Forward

    @Test func fForwardsWithNoRecipient() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("f")))

        #expect(app.route == .compose)
        #expect(app.compose.to.isEmpty)
        #expect(app.compose.subject == "Fwd: Invoice")
    }

    @Test func aForwardQuotesTheOriginal() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("f")))
        #expect(app.compose.body.contains("Forwarded message"))
        #expect(app.compose.body.contains("attached"))
    }

    @Test func aForwardCarriesTheAttachments() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("f")))

        // Forwarding an invoice without the invoice is useless.
        #expect(app.compose.attachments.map(\.filename) == ["invoice.pdf"])
    }

    @Test func aForwardIsNotAReply() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("f")))
        // If it were threaded, sending would deliver it to the original
        // participants -- the people being forwarded away from.
        #expect(!app.compose.isReply)
    }

    @Test func forwardingWithNothingSelectedIsHarmless() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: me),
            identity: me, isSignedIn: true)
        try app.start()

        app.handle(KeyInput(.character("f")))

        #expect(app.route == .list)
    }
}
