import Foundation
import SwiftUI
import VeloCore

public enum Route: Equatable, Sendable {
    case setup, list, thread, compose, palette
}

/// Owns which surface is focused and turns keystrokes into actions.
///
/// Routing is an explicit state machine because "which view is focused" is what
/// decides what a keystroke means -- `e` archives in the list and types a letter
/// in Compose.
@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var route: Route
    @Published public private(set) var syncStatus: SyncStatus = .idle

    public let inbox: InboxViewModel
    public let compose: ComposeViewModel
    public let palette = CommandRegistry.v1

    private let config: AppConfig
    private var keyboard = KeyboardEngine()

    public var setupHint: String { AppConfig.setupInstructions }
    public var isConfigured: Bool { config.isConfigured }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService, identity: String) {
        self.config = config
        self.inbox = InboxViewModel(store: store, outbound: outbound)
        self.compose = ComposeViewModel(outbound: outbound, identity: identity)
        self.route = config.isConfigured ? .list : .setup
    }

    public func start() throws {
        guard config.isConfigured else { return }
        try inbox.reload()
        route = .list
    }

    public func setSyncStatus(_ status: SyncStatus) { syncStatus = status }

    /// Feeds one keystroke through the keymap. Returns whether it was consumed:
    /// the event monitor must only swallow handled keys, or typing in a text
    /// field would fire triage actions.
    @discardableResult
    public func handle(_ input: KeyInput) -> Bool {
        // While composing, the text field owns the keyboard. Only Escape gets
        // through, so typing "e" in a message body cannot archive the inbox.
        if route == .compose {
            guard input.key == .escape else { return false }
            route = .list
            return true
        }

        switch keyboard.handle(input) {
        case .pending:
            return true
        case .unhandled:
            return false
        case let .action(action):
            perform(action)
            return true
        }
    }

    public func perform(_ action: MailAction) {
        switch action {
        case .moveSelectionDown: inbox.moveDown()
        case .moveSelectionUp: inbox.moveUp()
        case .openSelected: openSelected()
        case .archiveSelected: try? inbox.archiveSelected()
        case .reply: startReply()
        case .compose:
            compose.startNew()
            route = .compose
        case .send: send()
        case .goToInbox: route = .list
        case .back: goBack()
        case .openCommandPalette: route = .palette
        }
    }

    // MARK: - Internals

    private func openSelected() {
        guard inbox.selectedThread != nil else { return }
        // Opening a thread is what marks it read, exactly as in a real client.
        try? inbox.markSelectedRead()
        route = .thread
    }

    private func startReply() {
        guard let message = inbox.selectedMessages.last else { return }
        compose.startReply(to: message)
        route = .compose
    }

    private func send() {
        guard (try? compose.send()) != nil else { return }
        route = .list
        try? inbox.reload()
    }

    /// Escape backs out one level; from the list it does nothing, because there
    /// is nowhere further to go.
    private func goBack() {
        switch route {
        case .thread, .compose, .palette: route = .list
        case .list, .setup: break
        }
    }
}
