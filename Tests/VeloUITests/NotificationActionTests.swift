import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct NotificationActionTests {
    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<3 {
            let labels = ["INBOX", "UNREAD"]
            try store.upsert(MailThread(id: "t\(i)", sender: "a\(i)@x.com", snippet: "s",
                                        lastMessageDate: Date(timeIntervalSince1970: Double(100 - i)),
                                        isUnread: true, hasAttachments: false, labelIDs: labels))
            try store.upsert(Message(id: "m\(i)", threadID: "t\(i)", sender: "a\(i)@x.com",
                                     recipients: ["me@x.com"], subject: "s",
                                     date: Date(timeIntervalSince1970: Double(100 - i)),
                                     bodyHTML: nil, bodyText: "b", isUnread: true,
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

    // MARK: - Clicking one

    @Test func clickingABannerOpensTheThreadItWasAbout() throws {
        // The threadID was written onto every notification and read nowhere:
        // clicking one focused the app and left you where you already were.
        let (app, _) = try makeApp()
        app.inbox.select(index: 0)

        app.openFromNotification("t2")

        #expect(app.inbox.selectedThread?.id == "t2")
    }

    @Test func aBannerForSomethingSinceArchivedSaysSo() throws {
        // It can be filed on another device between the banner and the click.
        let (app, _) = try makeApp()
        app.openFromNotification("gone")
        #expect(app.notice == "That conversation is no longer in the inbox")
    }

    @Test func itGetsOutOfItsOwnWayFirst() throws {
        // A sheet over the list would swallow the thing just asked for.
        let (app, _) = try makeApp()
        app.perform(.showSenders)

        app.openFromNotification("t1")

        #expect(!app.isShowingSenders)
        #expect(app.inbox.selectedThread?.id == "t1")
    }

    @Test func itComesBackToTheInboxFromAnotherList() throws {
        let (app, _) = try makeApp()
        app.perform(.goToArchive)

        app.openFromNotification("t1")

        #expect(app.inbox.scope == .inbox)
        #expect(app.inbox.selectedThread?.id == "t1")
    }

    // MARK: - The two buttons

    @Test func archivingFromTheBannerFilesIt() throws {
        let (app, _) = try makeApp()
        app.archiveFromNotification("t1")
        #expect(!app.inbox.threads.contains { $0.id == "t1" })
    }

    @Test func aBannerArchiveIsStillUndoable() throws {
        // The same press from the same person deserves the same way back.
        let (app, _) = try makeApp()
        app.archiveFromNotification("t1")
        #expect(app.undoPrompt == "Archived")
        app.undo()
        #expect(app.inbox.threads.contains { $0.id == "t1" })
    }

    @Test func markingReadFromTheBannerClearsIt() throws {
        let (app, _) = try makeApp()
        app.markReadFromNotification("t1")
        #expect(app.inbox.threads.first { $0.id == "t1" }?.isUnread == false)
    }

    @Test func neitherButtonMovesTheReaderAnywhere() throws {
        // The point of Archive on a banner is not having to look at the app.
        let (app, _) = try makeApp()
        app.perform(.goToArchive)
        let scope = app.inbox.scope

        app.markReadFromNotification("t1")

        #expect(app.inbox.scope == scope)
    }
}
