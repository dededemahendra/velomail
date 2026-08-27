import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct BulkCommandTests {
    private func makeApp(unread: Int = 3, total: Int = 5) throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<total {
            let labels = i < unread ? ["INBOX", "UNREAD"] : ["INBOX"]
            try store.upsert(MailThread(id: "t\(i)", sender: "a\(i)@x.com", snippet: "s\(i)",
                                        lastMessageDate: Date(timeIntervalSince1970: Double(100 - i)),
                                        isUnread: i < unread, hasAttachments: false,
                                        labelIDs: labels))
            // A thread with no messages cannot carry a label change: the queue
            // applies to messages and re-derives the thread from them, so a
            // thread-only fixture silently makes every mutation a no-op.
            try store.upsert(Message(id: "m\(i)", threadID: "t\(i)", sender: "a\(i)@x.com",
                                     recipients: ["me@x.com"], subject: "s\(i)",
                                     date: Date(timeIntervalSince1970: Double(100 - i)),
                                     bodyHTML: nil, bodyText: "b", isUnread: i < unread,
                                     labelIDs: labels))
        }
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, store)
    }

    // MARK: - Select all

    @Test func oneKeystrokeStandsInForForty() throws {
        let (app, _) = try makeApp()
        app.perform(.selectAll)
        #expect(app.inbox.markedIndices.count == app.inbox.threads.count)
    }

    @Test func pressingItAgainClearsThem() throws {
        // What every other select-all in the system does.
        let (app, _) = try makeApp()
        app.perform(.selectAll)
        app.perform(.selectAll)
        #expect(app.inbox.markedIndices.isEmpty)
    }

    @Test func whatFollowsAppliesToAllOfThem() throws {
        let (app, _) = try makeApp()
        app.perform(.selectAll)
        app.perform(.archiveSelected)
        #expect(app.inbox.threads.isEmpty)
    }

    // MARK: - Mark all read

    @Test func itClearsEveryUnreadOneNotJustTheMarkedRows() throws {
        // "Mark all as read" that quietly meant "the two rows you ticked"
        // would be a trap.
        let (app, _) = try makeApp(unread: 3, total: 5)
        app.perform(.markAllRead)
        #expect(app.inbox.threads.allSatisfy { !$0.isUnread })
    }

    @Test func itSaysHowManyItTouched() throws {
        let (app, _) = try makeApp(unread: 3, total: 5)
        app.perform(.markAllRead)
        #expect(app.undoPrompt == "3 marked read")
    }

    @Test func fortyThreadsClearedAtOnceCanBeTakenBack() throws {
        // Archiving one thread had an undo and clearing forty did not, which
        // is exactly backwards.
        let (app, _) = try makeApp(unread: 3, total: 5)
        app.perform(.markAllRead)
        app.undo()
        #expect(app.inbox.threads.filter(\.isUnread).count == 3)
    }

    @Test func undoDoesNotUnreadWhatWasAlreadyRead() throws {
        // Only the ones actually changed are offered back.
        let (app, _) = try makeApp(unread: 2, total: 5)
        app.perform(.markAllRead)
        app.undo()
        #expect(app.inbox.threads.filter(\.isUnread).count == 2)
    }

    @Test func anAlreadyReadListSaysSoRatherThanNothing() throws {
        let (app, _) = try makeApp(unread: 0, total: 4)
        app.perform(.markAllRead)
        #expect(app.notice == "Nothing unread here")
    }

    // MARK: - Spam

    @Test func reportingSpamTakesItOutOfTheInbox() throws {
        let (app, _) = try makeApp()
        let before = app.inbox.threads.count
        app.perform(.reportSpam)
        #expect(app.inbox.threads.count == before - 1)
    }

    @Test func itAppliesToEveryMarkedRow() throws {
        let (app, _) = try makeApp()
        app.perform(.selectAll)
        app.perform(.reportSpam)
        #expect(app.inbox.threads.isEmpty)
        #expect(app.undoPrompt == "5 reported as spam")
    }

    @Test func aMisfiredSpamReportComesBack() throws {
        // Reporting the wrong thread as spam and having no way back is the
        // worst of the three, since it teaches Gmail as well.
        let (app, _) = try makeApp()
        let before = app.inbox.threads.count
        app.perform(.reportSpam)
        app.undo()
        #expect(app.inbox.threads.count == before)
    }

    // MARK: - Open in Gmail

    @Test func theEscapeHatchGoesToTheRightThread() throws {
        let (app, _) = try makeApp()
        var opened: URL?
        app.openURL = { opened = $0 }
        let id = try #require(app.inbox.selectedThread?.id)

        app.perform(.openInGmail)

        #expect(opened?.absoluteString.contains(id) == true)
        #expect(opened?.host == "mail.google.com")
    }

    // MARK: - Reachability

    @Test func allFiveAreInThePalette() {
        // Five features in this app were built and left unreachable.
        let titles = CommandRegistry.v1.commands.map(\.title)
        for title in ["Select all", "Mark all as read", "Report spam",
                      "Open in Gmail", "Export thread"] {
            #expect(titles.contains(title), "\(title) is missing from the palette")
        }
    }
}

@Suite struct SelectAllKeyTests {
    @Test func itSitsBesideTheKeyThatMarksOneRow() {
        #expect(KeyboardEngine.shortcutLabel(for: .toggleMark) == "X")
        #expect(KeyboardEngine.shortcutLabel(for: .selectAll) == "\u{21E7}X")
    }

    @Test func commandAIsLeftToTheSystem() {
        // While a message is open, Cmd+A selects the text inside it. Binding
        // it here would have the monitor swallow that.
        var engine = KeyboardEngine()
        #expect(engine.handle(KeyInput(.character("a"), [.command])) == .unhandled)
    }

    @Test func theMonitorLetsItThrough() {
        // A binding the event monitor filtered out was silently unreachable
        // once before: Cmd+, for settings was added, shipped, and did nothing.
        #expect(KeyboardEngine.boundCharacters.contains("x"))
    }
}
