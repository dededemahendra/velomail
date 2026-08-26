import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct TrashUnreadTests {
    private func makeApp(count: Int = 3) throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<count {
            let date = Date(timeIntervalSince1970: TimeInterval(100 - i))
            try store.upsert(MailThread(id: "t\(i)", sender: "a@b.com", snippet: "s",
                                        lastMessageDate: date, isUnread: false,
                                        hasAttachments: false, labelIDs: ["INBOX"]))
            try store.upsert(Message(id: "m\(i)", threadID: "t\(i)", sender: "a@b.com",
                                     recipients: [], subject: "s", date: date, bodyHTML: nil,
                                     bodyText: "b", isUnread: false, labelIDs: ["INBOX"]))
        }
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, store)
    }

    @Test func deleteBinsTheSelectedThreadAndAdvances() throws {
        let (app, store) = try makeApp()
        let target = try #require(app.inbox.selectedThread).id

        app.handle(KeyInput(.delete))

        #expect(!app.inbox.threads.contains { $0.id == target })
        #expect(try store.thread(id: target)?.labelIDs.contains("TRASH") == true)
        #expect(app.inbox.selectedThread != nil)      // advanced, not left empty
    }

    @Test func deleteIsNotArchive() throws {
        let (app, store) = try makeApp()
        let target = try #require(app.inbox.selectedThread).id

        app.handle(KeyInput(.delete))

        // Both leave the inbox; only one says where it went, which is what makes
        // it recoverable from another client.
        #expect(try store.thread(id: target)?.labelIDs.contains("TRASH") == true)
    }

    @Test func shiftUMarksUnreadAndLeavesItInPlace() throws {
        let (app, store) = try makeApp()
        let target = try #require(app.inbox.selectedThread).id

        app.handle(KeyInput(.character("u"), [.shift]))

        // The point is to come back to it, so it must not vanish or advance.
        #expect(try store.thread(id: target)?.isUnread == true)
        #expect(app.inbox.threads.contains { $0.id == target })
        #expect(app.inbox.selectedThread?.id == target)
    }

    @Test func plainUStillUnsubscribes() throws {
        let (app, _) = try makeApp()

        // Shift must not have swallowed the unsubscribe binding.
        #expect(app.handle(KeyInput(.character("u"))) == true)
    }

    @Test func deletingWithAnEmptyInboxIsHarmless() throws {
        let (app, _) = try makeApp(count: 0)
        app.handle(KeyInput(.delete))
        #expect(app.inbox.threads.isEmpty)
    }

    @Test func bothActionsAppearInThePaletteWithTheirKeys() {
        let titles = CommandRegistry.v1.commands.map(\.title)
        #expect(titles.contains("Delete"))
        #expect(titles.contains("Mark Unread"))
        #expect(KeyboardEngine.shortcutLabel(for: .trashSelected) == "⌫")
        #expect(KeyboardEngine.shortcutLabel(for: .markUnreadSelected) == "⇧U")
    }
}
