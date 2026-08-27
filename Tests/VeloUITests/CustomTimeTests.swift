import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct CustomTimeTests {
    private func makeApp() throws -> (AppViewModel, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let date = Date(timeIntervalSince1970: 100)
        try store.upsert(MailThread(id: "t", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: date, isUnread: false,
                                    hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: date, bodyHTML: nil, bodyText: "b",
                                 isUnread: false, labelIDs: ["INBOX"]))
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: mutations, identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, store, mutations)
    }

    // MARK: - Asking for a time

    @Test func chooseATimeOpensThePickerRatherThanActing() throws {
        // Nothing should happen to the mail until a time has been given.
        let (app, store, _) = try makeApp()

        app.perform(.snoozeAtTime)

        #expect(app.timeRequest?.purpose == .snooze)
        #expect(try store.snoozedThreads().isEmpty)
    }

    @Test func thePickerStartsSomewhereSensible() throws {
        // Not "now": every value the writer could want is in the future, and
        // starting in the past means every use begins by fixing it.
        let (app, _, _) = try makeApp()

        app.perform(.snoozeAtTime)

        #expect(try #require(app.timeRequest?.suggested) > Date())
    }

    @Test func confirmingSnoozesToThatTime() throws {
        let (app, store, _) = try makeApp()
        let when = Date().addingTimeInterval(9_000)
        app.perform(.snoozeAtTime)

        app.confirmTime(when)

        #expect(try store.snoozedThreads().map(\.id) == ["t"])
        #expect(app.timeRequest == nil)
    }

    @Test func cancellingLeavesTheMailAlone() throws {
        let (app, store, _) = try makeApp()
        app.perform(.snoozeAtTime)

        app.cancelTime()

        #expect(app.timeRequest == nil)
        #expect(try store.snoozedThreads().isEmpty)
        #expect(try store.inboxThreads().map(\.id) == ["t"])
    }

    // MARK: - Sending at a time

    @Test func sendingAtATimeSchedulesIt() throws {
        let (app, _, _) = try makeApp()
        app.compose.startNew()
        app.compose.to = "bob@x.com"
        app.compose.subject = "Later"
        app.compose.body = "b"

        app.perform(.sendAtTime)
        app.confirmTime(Date().addingTimeInterval(86_400))

        #expect(app.scheduled.count == 1)
    }

    @Test func aTimeInThePastStillWaitsOutTheUndoWindow() throws {
        // Confirming "yesterday" should not send instantly and unrecallably.
        let (app, _, _) = try makeApp()
        app.compose.startNew()
        app.compose.to = "bob@x.com"
        app.compose.subject = "Oops"
        app.compose.body = "b"

        app.perform(.sendAtTime)
        app.confirmTime(Date().addingTimeInterval(-86_400))

        #expect(app.undoPrompt == "Message sent")
    }

    @Test func bothAreInTheCommandPalette() throws {
        let titles = CommandRegistry.v1.commands.map(\.title)
        #expect(titles.contains { $0.lowercased().contains("snooze until") && $0.contains("…") })
        #expect(titles.contains { $0.lowercased().contains("send at") })
    }
}
