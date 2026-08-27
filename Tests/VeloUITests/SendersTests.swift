import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct SendersTests {
    /// A scratch config directory: `alwaysArchive` writes a rules file, and it
    /// must never be the reader's own.
    private func scratchSettings() -> (SettingsStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-rules-\(UUID().uuidString)")
        return (SettingsStore(directory: dir), dir)
    }

    private func makeApp(_ settings: SettingsStore) throws -> (AppViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        // Nine from one address, one from another: this mailbox's real shape.
        for i in 0..<9 {
            try add(store, id: "x\(i)", sender: "Xero <billing@xero.com>",
                    unread: i < 3, unsubscribe: i == 0 ? "<mailto:off@xero.com>" : nil)
        }
        try add(store, id: "p", sender: "Peta Bilston <peta@example.com>")
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, settingsStore: settings)
        try app.start()
        return (app, store)
    }

    private func add(_ store: MailStore, id: String, sender: String,
                     unread: Bool = false, unsubscribe: String? = nil) throws {
        try store.upsert(MailThread(id: id, sender: sender, snippet: "s",
                                    lastMessageDate: Date(), isUnread: unread,
                                    hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: sender,
                                 recipients: ["me@x.com"], subject: "s", date: Date(),
                                 bodyHTML: nil, bodyText: "b", isUnread: unread,
                                 labelIDs: ["INBOX"], listUnsubscribe: unsubscribe))
    }

    // MARK: - Seeing it

    @Test func itSaysWhoIsFillingTheInbox() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)

        app.perform(.showSenders)

        #expect(app.isShowingSenders)
        #expect(app.senders.first?.address == "billing@xero.com")
        #expect(app.senders.first?.threads == 9)
        #expect(app.senders.first?.unread == 3)
    }

    @Test func aSenderKnowsTheirShare() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        // Nine of ten. 84% of this mailbox is ten senders and nothing said so.
        #expect(abs((app.senders.first?.share(of: 10) ?? 0) - 0.9) < 0.001)
    }

    // MARK: - Acting on one

    @Test func archivingAllOfThemIsOneStep() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)
        let loud = try #require(app.senders.first)

        app.archiveAll(from: loud)

        #expect(app.inbox.threads.count == 1)
    }

    @Test func aSweepIsOneOfferNotFourHundred() throws {
        // Four hundred banners would bury the only one that matters.
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.archiveAll(from: try #require(app.senders.first))

        #expect(app.undoPrompt?.contains("9 archived") == true)
        app.undo()
        #expect(app.inbox.threads.count == 10)
    }

    @Test func alwaysArchiveFilesARuleAndClearsWhatIsAlreadyThere() throws {
        // A rule that only applies to future mail leaves the four hundred
        // already sitting there, which is why you opened the screen.
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.alwaysArchive(from: try #require(app.senders.first))

        let rules = settings.rules().rules
        #expect(rules.count == 1)
        #expect(rules[0].conditions == [.senderContains("billing@xero.com")])
        #expect(rules[0].actions == [.archive])
        #expect(app.inbox.threads.count == 1)
    }

    @Test func askingTwiceDoesNotFileTheRuleTwice() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)
        let loud = try #require(app.senders.first)

        app.alwaysArchive(from: loud)
        app.alwaysArchive(from: loud)

        #expect(settings.rules().rules.count == 1)
        #expect(app.notice?.contains("Already archiving") == true)
    }

    @Test func theRuleMatchesTheAddressNotTheFriendlyName() throws {
        // Bulk senders change the name on every send and never the address.
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.alwaysArchive(from: try #require(app.senders.first))

        #expect(settings.rules().rules[0].conditions == [.senderContains("billing@xero.com")])
    }

    @Test func unsubscribingUsesALinkFromAnyOfTheirMessages() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.unsubscribe(from: try #require(app.senders.first))

        #expect(app.undoPrompt?.contains("Unsubscribing from") == true)
    }

    @Test func aSenderWithNoLinkSaysSoRatherThanDoingNothing() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)
        let quiet = try #require(app.senders.first { $0.address == "peta@example.com" })

        app.unsubscribe(from: quiet)

        #expect(app.notice == "No unsubscribe link on this sender")
    }

    @Test func openingOneLandsOnTheirMail() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.openSenderInInbox(try #require(app.senders.first))

        #expect(!app.isShowingSenders)
        #expect(app.inbox.selectedThread?.sender.contains("xero.com") == true)
    }

    // MARK: - The sheet owns the keyboard

    @Test func keysDoNotReachTheListUnderneath() throws {
        // A sheet is on top of the list, not beside it. Without this, e
        // archived a thread nobody could see.
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)
        let before = app.inbox.threads.count

        app.handle(KeyInput(.character("x")))     // mark, in the list
        app.handle(KeyInput(.character("s")))     // star, in the list

        #expect(app.inbox.threads.count == before)
        #expect(app.inbox.markedIndices.isEmpty)
    }

    @Test func jAndKWalkTheSenders() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.handle(KeyInput(.character("j")))
        #expect(app.selectedSender == 1)
        app.handle(KeyInput(.character("k")))
        #expect(app.selectedSender == 0)
    }

    @Test func theCursorStopsAtBothEnds() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.handle(KeyInput(.character("k")))
        #expect(app.selectedSender == 0)
        for _ in 0..<10 { app.handle(KeyInput(.character("j"))) }
        #expect(app.selectedSender == app.senders.count - 1)
    }

    @Test func eArchivesTheSenderNotTheThread() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.handle(KeyInput(.character("e")))

        #expect(app.inbox.threads.count == 1)
    }

    @Test func escapeClosesIt() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        app.perform(.showSenders)

        app.handle(KeyInput(.escape))

        #expect(!app.isShowingSenders)
    }

    @Test func theOtherSheetsAlsoOwnTheirKeys() throws {
        let (settings, dir) = scratchSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (app, _) = try makeApp(settings)
        let before = app.inbox.threads.count

        app.perform(.openSettings)
        app.handle(KeyInput(.character("e")))
        #expect(app.inbox.threads.count == before)

        app.handle(KeyInput(.escape))
        #expect(!app.isShowingSettings)
    }

    // MARK: - Reachability

    @Test func itIsReachableBothWays() {
        #expect(CommandRegistry.v1.commands.map(\.title).contains("Senders"))
        #expect(KeyboardEngine.shortcutLabel(for: .showSenders) == "G U")
    }
}
