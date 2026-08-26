import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct NotificationStateTests {
    private func makeApp(unread: Int, total: Int = 4) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<total {
            let isUnread = i < unread
            let labels = isUnread ? ["INBOX", "UNREAD"] : ["INBOX"]
            try store.upsert(MailThread(id: "t\(i)", sender: "a@b.com", snippet: "s",
                                        lastMessageDate: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                        isUnread: isUnread, hasAttachments: false, labelIDs: labels))
            try store.upsert(Message(id: "m\(i)", threadID: "t\(i)", sender: "a@b.com",
                                     recipients: [], subject: "s",
                                     date: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                     bodyHTML: nil, bodyText: "b", isUnread: isUnread,
                                     labelIDs: labels))
        }
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return app
    }

    @Test func unreadCountsOnlyUnreadThreads() throws {
        #expect(try makeApp(unread: 2).unreadCount == 2)
    }

    @Test func anAllReadInboxCountsZero() throws {
        #expect(try makeApp(unread: 0).unreadCount == 0)
    }

    @Test func focusIsOffByDefault() throws {
        #expect(try makeApp(unread: 1).isFocused == false)
    }

    @Test func focusHidesTheUnreadCount() throws {
        let app = try makeApp(unread: 3)

        app.toggleFocus()

        // The point of focus is not knowing how much is waiting.
        #expect(app.isFocused)
        #expect(app.visibleUnreadCount == 0)
        #expect(app.unreadCount == 3)      // the fact is still there underneath
    }

    @Test func leavingFocusRestoresTheCount() throws {
        let app = try makeApp(unread: 3)
        app.toggleFocus()

        app.toggleFocus()

        #expect(app.visibleUnreadCount == 3)
    }

    @Test func focusSuppressesAnnouncements() throws {
        let app = try makeApp(unread: 1)
        app.toggleFocus()
        #expect(app.shouldAnnounce == false)
    }

    @Test func announcementsAreAllowedWhenNotFocused() throws {
        #expect(try makeApp(unread: 1).shouldAnnounce)
    }

    @Test func markingAThreadReadDropsTheCount() throws {
        let app = try makeApp(unread: 2)
        try app.inbox.markSelectedRead()
        try app.inbox.reload()
        #expect(app.unreadCount == 1)
    }

    @Test func theFocusChordTogglesIt() throws {
        let app = try makeApp(unread: 2)

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("d")))

        #expect(app.isFocused)
        #expect(app.visibleUnreadCount == 0)
    }

    @Test func theFocusChordTogglesBackOff() throws {
        let app = try makeApp(unread: 2)
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("d")))

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("d")))

        #expect(!app.isFocused)
        #expect(app.visibleUnreadCount == 2)
    }
}

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}
