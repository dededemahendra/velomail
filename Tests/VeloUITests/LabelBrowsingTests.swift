import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct LabelBrowsingTests {
    private func makeApp() throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.replaceLabels([
            MailLabel(id: "Label_7", name: "Clients", kind: .user),
            MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system),
            MailLabel(id: "INBOX", name: "INBOX", kind: .system),
        ])
        try seed(store, id: "client", labels: ["INBOX", "Label_7"], at: 30)
        try seed(store, id: "update", labels: ["INBOX", "CATEGORY_UPDATES"], at: 20)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return (app, store)
    }

    private func seed(_ store: MailStore, id: String, labels: [String], at seconds: TimeInterval) throws {
        let date = Date(timeIntervalSince1970: seconds)
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s", lastMessageDate: date,
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: "a@b.com", recipients: [],
                                 subject: "s", date: date, bodyHTML: nil, bodyText: "b",
                                 isUnread: false, labelIDs: labels))
    }

    // MARK: - Looking at one

    @Test func theBrowsableLabelsAreOffered() throws {
        let (app, _) = try makeApp()
        #expect(app.labels.map(\.displayName) == ["Updates", "Clients"])
    }

    @Test func openingALabelShowsOnlyItsMail() throws {
        let (app, _) = try makeApp()

        app.show(label: MailLabel(id: "Label_7", name: "Clients", kind: .user))

        #expect(app.inbox.threads.map(\.id) == ["client"])
        #expect(app.inbox.title == "Clients")
    }

    @Test func aCategoryIsTitledAsAWord() throws {
        let (app, _) = try makeApp()
        app.show(label: MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system))
        #expect(app.inbox.title == "Updates")
    }

    @Test func goingBackToTheInboxLeavesTheLabel() throws {
        let (app, _) = try makeApp()
        app.show(label: MailLabel(id: "Label_7", name: "Clients", kind: .user))

        app.perform(.goToInbox)

        #expect(app.inbox.scope == .inbox)
        #expect(app.inbox.threads.count == 2)
    }

    // MARK: - Filing something

    @Test func filingAThreadPutsItUnderTheLabel() throws {
        let (app, _) = try makeApp()
        let filed = try #require(app.inbox.selectedThread?.id)

        app.applyLabel(MailLabel(id: "Label_7", name: "Clients", kind: .user))
        app.show(label: MailLabel(id: "Label_7", name: "Clients", kind: .user))

        #expect(app.inbox.threads.map(\.id).contains(filed))
    }

    @Test func filingIsUndoableLikeAnythingElse() throws {
        let (app, _) = try makeApp()
        app.applyLabel(MailLabel(id: "Label_7", name: "Clients", kind: .user))
        #expect(app.undoPrompt == "Filed")
    }

    @Test func filingSomethingAlreadyThereChangesNothing() throws {
        let (app, _) = try makeApp()
        app.show(label: MailLabel(id: "Label_7", name: "Clients", kind: .user))
        let before = app.inbox.threads.count

        app.applyLabel(MailLabel(id: "Label_7", name: "Clients", kind: .user))

        #expect(app.inbox.threads.count == before)
    }

    @Test func labelsAreInTheCommandPalette() throws {
        // The palette is where a keyboard-first client puts anything that does
        // not deserve a key of its own, and there is one label per account.
        let (app, _) = try makeApp()
        #expect(app.palette.commands.contains { $0.title == "Go to Clients" })
        #expect(app.palette.commands.contains { $0.title == "File in Clients" })
    }
}
