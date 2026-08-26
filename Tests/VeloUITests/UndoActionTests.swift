import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct UndoActionTests {
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

    @Test func archivingOffersAnUndo() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.character("e")))

        #expect(app.undoPrompt == "Archived")
    }

    @Test func undoingAnArchivePutsItBack() throws {
        let (app, _) = try makeApp()
        let target = try #require(app.inbox.selectedThread).id

        app.handle(KeyInput(.character("e")))
        app.handle(KeyInput(.character("z"), [.command]))

        // e auto-advances, so a mis-press moves you on before you notice.
        #expect(app.inbox.threads.contains { $0.id == target })
        #expect(app.undoPrompt == nil)
    }

    @Test func deletingOffersAnUndoThatSaysDeleted() throws {
        let (app, _) = try makeApp()

        app.handle(KeyInput(.delete))

        #expect(app.undoPrompt == "Deleted")
    }

    @Test func undoingADeleteRestoresItFromTheBin() throws {
        let (app, store) = try makeApp()
        let target = try #require(app.inbox.selectedThread).id

        app.handle(KeyInput(.delete))
        app.handle(KeyInput(.character("z"), [.command]))

        #expect(try store.thread(id: target)?.labelIDs.contains("TRASH") == false)
        #expect(app.inbox.threads.contains { $0.id == target })
    }

    @Test func undoingRestoresEverythingInABulkAction() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("x")))       // mark first
        app.handle(KeyInput(.character("j")))
        app.handle(KeyInput(.character("x")))       // mark second
        let before = app.inbox.threads.count

        app.handle(KeyInput(.character("e")))
        app.handle(KeyInput(.character("z"), [.command]))

        #expect(app.inbox.threads.count == before)
    }

    @Test func sendingStillOffersItsOwnUndo() throws {
        let (app, _) = try makeApp()
        app.perform(.compose)
        app.compose.to = "a@b.com"
        app.compose.body = "hi"

        app.perform(.send)

        #expect(app.undoPrompt == "Message sent")
    }

    @Test func aNewerActionReplacesTheOlderUndo() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("e")))
        #expect(app.undoPrompt == "Archived")

        app.handle(KeyInput(.delete))

        // Only the most recent thing is undoable; offering a stale one would
        // undo something the user has stopped thinking about.
        #expect(app.undoPrompt == "Deleted")
    }

    @Test func undoingWithNothingToUndoIsHarmless() throws {
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("z"), [.command]))
        #expect(app.undoPrompt == nil)
    }

    @Test func theBannerIconMatchesWhatCanBeTakenBack() throws {
        // Carried with the action rather than read back out of the wording.
        let (app, _) = try makeApp()
        app.handle(KeyInput(.character("e")))
        #expect(app.undoSymbol == "arrow.uturn.backward")
    }
}
