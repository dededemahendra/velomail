import Foundation
import SwiftUI
import GRDB
import VeloCore

/// Owns the assembled app and the background sync task for the process
/// lifetime. Split from `AppViewModel` so the view model stays a pure,
/// testable object with no `Task` or filesystem in it.
@MainActor
final class AppHost: ObservableObject {
    /// Republished when the account changes, which is what rebuilds the whole
    /// view tree onto the other mailbox.
    @Published private(set) var app: AppViewModel
    /// Which mailboxes exist and which one is open.
    let accounts = AccountList()
    /// Published separately so the view tree can key on it.
    @Published private(set) var currentAccountID = AccountList().current
    private var sync: GmailSync?
    private var store: MailStore
    private var auth: AuthCoordinator?
    private let notifications = NotificationPresenter()
    private var syncTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    /// Must be retained: GRDB cancels the observation when this is released,
    /// which would silently stop the list ever repainting on sync.
    private var inboxObservation: AnyDatabaseCancellable?

    init() {
        // A failure here means the store could not be opened at all, which is
        // unrecoverable; fall back to an in-memory one so the window still
        // appears and can explain itself rather than the app dying on launch.
        let assembly = (try? Composition.make(accountID: AccountList().current))
            ?? AppHost.fallback()
        self.app = assembly.app
        self.sync = assembly.sync
        self.store = assembly.store
        self.auth = assembly.auth
        wire()
    }

    /// Hands the new view model its callbacks. Called on every account change,
    /// because each account has an assembly of its own.
    private func wire() {
        // The view model routes; the coordinator owns the browser hop.
        app.onSignInRequested = { [weak self] in self?.auth?.signIn() }
        app.accounts = accounts.accounts
        app.currentAccount = accounts.current
        app.onSwitchAccount = { [weak self] id in Task { await self?.switchTo(id) } }
        app.onAddAccount = { [weak self] in
            guard let self else { return }
            Task { await self.switchTo(self.accounts.add()) }
        }
    }

    /// Closes the current mailbox and opens another.
    ///
    /// Everything is rebuilt rather than reconfigured: two accounts share no
    /// database, no tokens and no sync cursor, so the only thing they could
    /// share is a bug.
    func switchTo(_ accountID: String) async {
        guard accountID != accounts.current || sync == nil else { return }
        accounts.switchTo(accountID)
        currentAccountID = accounts.current
        stop()
        inboxObservation = nil

        let assembly = (try? Composition.make(accountID: accounts.current))
            ?? AppHost.fallback()
        app = assembly.app
        sync = assembly.sync
        store = assembly.store
        auth = assembly.auth
        wire()
        await start()
    }

    func start() async {
        try? app.start()
        observeInbox()
        await observeAuth()
        // Learned from Gmail's profile, so it is only known once mail arrives.
        if !app.identity.isEmpty { accounts.setAddress(app.identity, on: accounts.current) }
        app.accounts = accounts.accounts
        await notifications.requestAuthorizationIfNeeded()
        announceNewMail()
        guard let sync else { return }
        syncTask = Task { [interval = app.preferences.syncInterval] in
            await sync.run(interval: interval)
        }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                if let status = await self?.sync?.status {
                    self?.app.setSyncStatus(status)
                    // A sign-in that has expired is not a status to display and
                    // wait out; it is the one failure the reader can fix, and
                    // the app should say so where signing in happens.
                    if case let .failed(reason) = status,
                       reason.contains("Sign in again") {
                        self?.app.setSignedIn(false)
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        statusTask?.cancel()
    }

    /// Mirrors sign-in state into the view model so routing reacts to it.
    private func observeAuth() async {
        guard let auth else { return }
        auth.onStateChange = { [weak self] state in self?.app.setAuthState(state) }
        // Reads the Keychain off the main actor, so the window can draw while
        // an authorisation prompt is waiting to be answered.
        await auth.restoreState()
        app.setAuthState(auth.state)
    }

    /// Announces anything new and refreshes the badge.
    ///
    /// Driven off the same observation that repaints the list, so a banner
    /// appears exactly when the mail does rather than on a timer of its own.
    private func announceNewMail() {
        guard app.preferences.showsNotifications else {
            notifications.setBadge(0)
            return
        }
        notifications.setBadge(app.visibleUnreadCount)
        guard app.shouldAnnounce else { return }

        let messages = (try? store.recentInboxMessages(limit: 100)) ?? []
        let result = MailAnnouncer(blocklist: RuleEngine(rules: RuleLibrary.load().rules)).announce(messages: messages,
                                              identity: app.identity,
                                              since: notifications.announcedThrough)
        notifications.present(result)
        notifications.announcedThrough = result.highWaterMark
    }

    /// Repaints the list whenever sync lands rows, so the UI never polls.
    private func observeInbox() {
        inboxObservation = store.observeInboxThreads { [weak app, weak self] _ in
            Task { @MainActor in
                try? app?.inbox.reload()
                self?.announceNewMail()
            }
        }
    }

    private static func fallback() -> Composition.Assembly {
        let database = try! AppDatabase.makeInMemory()
        let store = MailStore(database)
        let outbound = OutboundService(writer: LocalOnlyWriter(), store: store,
                                       mutations: MutationStore(database), identity: "me@localhost")
        return Composition.Assembly(
            app: AppViewModel(config: AppConfig(clientID: nil, clientSecret: nil, isDemo: false, demoRoute: nil),
                              store: store, outbound: outbound, identity: "me@localhost"),
            sync: nil, store: store, auth: nil)
    }
}
