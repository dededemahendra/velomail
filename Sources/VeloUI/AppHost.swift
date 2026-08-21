import Foundation
import SwiftUI
import VeloCore

/// Owns the assembled app and the background sync task for the process
/// lifetime. Split from `AppViewModel` so the view model stays a pure,
/// testable object with no `Task` or filesystem in it.
@MainActor
final class AppHost: ObservableObject {
    let app: AppViewModel
    private let sync: GmailSync?
    private let store: MailStore
    private var syncTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init() {
        // A failure here means the store could not be opened at all, which is
        // unrecoverable; fall back to an in-memory one so the window still
        // appears and can explain itself rather than the app dying on launch.
        let assembly = (try? Composition.make()) ?? AppHost.fallback()
        self.app = assembly.app
        self.sync = assembly.sync
        self.store = assembly.store
    }

    func start() async {
        try? app.start()
        observeInbox()
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

    /// Repaints the list whenever sync lands rows, so the UI never polls.
    private func observeInbox() {
        store.observeInboxThreads { [weak app] _ in
            Task { @MainActor in try? app?.inbox.reload() }
        }
    }

    private static func fallback() -> Composition.Assembly {
        let database = try! AppDatabase.makeInMemory()
        let store = MailStore(database)
        let outbound = OutboundService(writer: LocalOnlyWriter(), store: store,
                                       mutations: MutationStore(database), identity: "me@example.com")
        return Composition.Assembly(
            app: AppViewModel(config: AppConfig(clientID: nil, isDemo: false),
                              store: store, outbound: outbound, identity: "me@example.com"),
            sync: nil, store: store)
    }
}
