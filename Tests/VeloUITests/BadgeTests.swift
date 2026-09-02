import Testing
import AppKit
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

/// The Dock badge had no test of any kind.
///
/// It is one line -- `dockTile.badgeLabel = ...` -- and one line is exactly
/// where this project has been bitten before: a value written for a consumer
/// that turned out not to exist. These check both halves: that the number is
/// the right number, and that writing it actually reaches the Dock.
@MainActor
@Suite struct BadgeTests {
    private func makeApp(unread: Int, read: Int = 0) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<(unread + read) {
            try store.upsert(MailThread(id: "t\(i)", sender: "a@b.com", snippet: "s",
                                        lastMessageDate: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                        isUnread: i < unread, hasAttachments: false,
                                        labelIDs: ["INBOX"]))
        }
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return app
    }

    // MARK: - The number

    @Test func theBadgeCountsUnreadInboxThreads() throws {
        let app = try makeApp(unread: 7, read: 4)
        #expect(app.visibleUnreadCount == 7)
    }

    /// Counted over the whole inbox, not the visible rows. Nothing pages the
    /// list, and if anything ever does, a badge that counts what is on screen
    /// would start under-reporting silently.
    @Test func theBadgeCountsEveryUnreadThreadNotJustTheLoadedOnes() throws {
        let app = try makeApp(unread: 300)
        #expect(app.visibleUnreadCount == 300)
        #expect(app.inbox.threads.count == 300)
    }

    /// Focus hides how much is waiting -- that is the point of it.
    @Test func focusHidesTheNumberWithoutHidingTheMail() throws {
        let app = try makeApp(unread: 7)
        app.toggleFocus()

        #expect(app.visibleUnreadCount == 0)
        #expect(app.inbox.threads.count == 7, "focus hid the mail, not just the count")
    }

    @Test func anInboxWithNothingUnreadShowsNoNumber() throws {
        #expect(try makeApp(unread: 0, read: 5).visibleUnreadCount == 0)
    }

    // MARK: - Reaching the Dock

    /// The half that could silently do nothing.
    @Test func settingTheBadgePutsItOnTheDockTile() {
        let presenter = NotificationPresenter()

        presenter.setBadge(12)
        #expect(NSApplication.shared.dockTile.badgeLabel == "12")

        presenter.setBadge(1)
        #expect(NSApplication.shared.dockTile.badgeLabel == "1")
    }

    /// Zero clears it rather than printing "0". A badge saying nothing is
    /// waiting is worse than no badge.
    @Test func zeroClearsTheBadgeRatherThanShowingAZero() {
        let presenter = NotificationPresenter()
        presenter.setBadge(9)
        #expect(NSApplication.shared.dockTile.badgeLabel != nil)

        presenter.setBadge(0)
        #expect(NSApplication.shared.dockTile.badgeLabel == nil)
    }

    // MARK: - Which mailbox it counts

    /// The badge counts the inbox. It was counting `inbox.threads`, which is
    /// whichever list is on screen -- so opening Sent, or Starred, or a label
    /// silently rewrote the number on the Dock to that list's unread count.
    @Test func theBadgeCountsTheInboxWhicheverListIsOpen() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        for i in 0..<6 {
            try store.upsert(MailThread(id: "in\(i)", sender: "a@b.com", snippet: "s",
                                        lastMessageDate: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                        isUnread: true, hasAttachments: false, labelIDs: ["INBOX"]))
        }
        // One sent thread, read, which is the ordinary case for Sent.
        try store.upsert(MailThread(id: "s1", sender: "me@x.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 50),
                                    isUnread: false, hasAttachments: false, labelIDs: ["SENT"]))
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        #expect(app.visibleUnreadCount == 6)

        try app.inbox.show(.sent)
        #expect(app.inbox.threads.count == 1, "the list really did change")

        #expect(app.visibleUnreadCount == 6, "the badge followed the open list")
    }

    /// A snoozed conversation is not in the inbox, so it is not waiting. The
    /// list already hides it; the badge has to agree, or the number on the Dock
    /// counts mail that is not there.
    @Test func snoozedMailIsNotCountedWhileItIsAway() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "here", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: true, hasAttachments: false, labelIDs: ["INBOX"]))
        var away = MailThread(id: "away", sender: "a@b.com", snippet: "s",
                              lastMessageDate: Date(timeIntervalSince1970: 90),
                              isUnread: true, hasAttachments: false, labelIDs: ["INBOX"])
        away.snoozedUntil = Date().addingTimeInterval(86_400)
        try store.upsert(away)

        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()

        #expect(app.inbox.threads.count == 1)
        #expect(app.visibleUnreadCount == 1, "counted a conversation that is snoozed away")
    }
}
