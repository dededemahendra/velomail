import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct SnoozeUITests {
    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<2 {
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

    // MARK: - Seeing what was snoozed

    @Test func gHShowsTheSnoozedList() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("h")))

        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("h")))

        #expect(app.inbox.scope == .snoozed)
        #expect(app.inbox.threads.map(\.id) == ["t0"])
        #expect(app.inbox.title == "Snoozed")
    }

    @Test func theInboxNoLongerHoldsIt() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("h")))
        #expect(app.inbox.threads.map(\.id) == ["t1"])
    }

    // MARK: - Choosing when

    @Test func aSnoozeCanBeGivenALongerHorizon() throws {
        let (app, store) = try makeApp()
        let before = Date()

        app.perform(.snoozeUntilTomorrow)

        let woken = try #require(try store.thread(id: "t0")?.snoozedUntil)
        #expect(woken > before.addingTimeInterval(12 * 3_600))
    }

    @Test func nextWeekIsFurtherOutThanTomorrow() throws {
        let (app, store) = try makeApp()
        app.perform(.snoozeUntilTomorrow)
        let tomorrow = try #require(try store.thread(id: "t0")?.snoozedUntil)

        app.perform(.snoozeUntilNextWeek)
        let nextWeek = try #require(try store.thread(id: "t1")?.snoozedUntil)

        #expect(nextWeek > tomorrow)
    }

    @Test func everyDurationIsInTheCommandPalette() throws {
        // The chord for `h` stays a single keystroke, so the other horizons
        // have to be reachable somewhere the writer can find them.
        let titles = CommandRegistry.v1.commands.map(\.title)
        #expect(titles.contains { $0.contains("tomorrow") })
        #expect(titles.contains { $0.contains("next week") })
    }

    // MARK: - Taking it back

    @Test func unsnoozingFromTheListReturnsItToTheInbox() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("h")))
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("h")))

        app.perform(.unsnoozeSelected)

        #expect(app.inbox.threads.isEmpty)          // gone from Snoozed
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("i")))
        #expect(app.inbox.threads.map(\.id).sorted() == ["t0", "t1"])
    }

    @Test func unsnoozingCanBeUndone() throws {
        // It is the same class of gesture as an archive: reversible.
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("h")))
        #expect(app.undoPrompt == "Snoozed")
    }

    @Test func aSnoozedRowShowsWhenItComesBack() throws {
        // The received date is the one thing the writer already knows about a
        // thread they chose to put away. When it returns is the open question.
        let (app, _) = try makeApp()
        app.perform(.snoozeUntilTomorrow)
        app.handle(KeyInput(.character("g")))
        app.handle(KeyInput(.character("h")))

        let thread = try #require(app.inbox.threads.first)
        #expect(app.inbox.rowDate(of: thread)
                == MailFormatting.wakeTime(try #require(thread.snoozedUntil)))
    }

    @Test func otherListsStillShowTheReceivedDate() throws {
        let (app, _) = try makeApp()
        let thread = try #require(app.inbox.threads.first)
        #expect(app.inbox.rowDate(of: thread)
                == MailFormatting.relativeDate(thread.lastMessageDate))
    }
}
