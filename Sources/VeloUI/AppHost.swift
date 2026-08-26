import Foundation
import SwiftUI
import GRDB
import VeloCore

/// Owns the assembled app and the background sync task for the process
/// lifetime. Split from `AppViewModel` so the view model stays a pure,
/// testable object with no `Task` or filesystem in it.
@MainActor
final class AppHost: ObservableObject {
    let app: AppViewModel
    private let sync: GmailSync?
    private let store: MailStore
    private let auth: AuthCoordinator?
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
        let assembly = (try? Composition.make()) ?? AppHost.fallback()
        self.app = assembly.app
        self.sync = assembly.sync
        self.store = assembly.store
        self.auth = assembly.auth
        // The view model routes; the coordinator owns the browser hop.
        app.onSignInRequested = { [weak self] in self?.auth?.signIn() }
    }

    func start() async {
        try? app.start()
        observeInbox()
        observeAuth()
        await notifications.requestAuthorizationIfNeeded()
        announceNewMail()
        guard let sync else { return }
        syncTask = Task { await sync.run(interval: 60) }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                if let status = await self?.sync?.status { self?.app.setSyncStatus(status) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        syncTask?.cancel()
        statusTask?.cancel()
    }

    /// Mirrors sign-in state into the view model so routing reacts to it.
    private func observeAuth() {
        guard let auth else { return }
        auth.onStateChange = { [weak self] state in self?.app.setAuthState(state) }
        app.setAuthState(auth.state)
    }

    /// Announces anything new and refreshes the badge.
    ///
    /// Driven off the same observation that repaints the list, so a banner
    /// appears exactly when the mail does rather than on a timer of its own.
    private func announceNewMail() {
        notifications.setBadge(app.visibleUnreadCount)
        guard app.shouldAnnounce else { return }

        let messages = (try? store.recentInboxMessages(limit: 100)) ?? []
        let result = MailAnnouncer().announce(messages: messages,
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
            app: AppViewModel(config: AppConfig(clientID: nil, isDemo: false),
                              store: store, outbound: outbound, identity: "me@localhost"),
            sync: nil, store: store, auth: nil)
    }
}
