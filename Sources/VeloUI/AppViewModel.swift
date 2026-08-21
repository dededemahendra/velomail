import Foundation
import SwiftUI
import VeloCore

public enum Route: Equatable, Sendable {
    case setup, signIn, list, thread, compose, palette
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
    @Published public private(set) var authState: AuthCoordinator.AuthState = .signedOut

    /// Set by `AppHost`, which owns the coordinator; the view model only routes.
    public var onSignInRequested: (() -> Void)?

    public let inbox: InboxViewModel
    public let compose: ComposeViewModel
    public let palette = CommandRegistry.v1

    private let config: AppConfig
    private var keyboard = KeyboardEngine()
    private var isSignedIn: Bool

    public var setupHint: String { AppConfig.setupInstructions }
    public var isConfigured: Bool { config.isConfigured }

    /// Demo mode exists precisely to be looked at without credentials, so it
    /// must reach the mail surface even though it has no client id. Only a
    /// genuinely unconfigured launch goes to setup.
    private var canShowMail: Bool { config.isDemo || (config.isConfigured && isSignedIn) }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService,
                identity: String, isSignedIn: Bool = false) {
        self.config = config
        self.isSignedIn = isSignedIn
        self.inbox = InboxViewModel(store: store, outbound: outbound)
        self.compose = ComposeViewModel(outbound: outbound, identity: identity)
        self.route = .setup
        self.route = landingRoute
    }

    public func start() throws {
        guard canShowMail else {
            route = landingRoute
            return
        }
        try inbox.reload()
        route = .list
    }

    /// Sign-in state changed underneath us (the browser leg finished, or the
    /// user signed out).
    public func setSignedIn(_ signedIn: Bool) {
        isSignedIn = signedIn
        route = landingRoute
        if route == .list { try? inbox.reload() }
    }

    /// Where a fresh launch lands. Order matters: with no credentials there is
    /// nothing to sign in *to*, so setup comes first.
    private var landingRoute: Route {
        if config.isDemo { return .list }
        guard config.isConfigured else { return .setup }
        return isSignedIn ? .list : .signIn
    }

    public func setSyncStatus(_ status: SyncStatus) { syncStatus = status }

    public func setAuthState(_ state: AuthCoordinator.AuthState) {
        authState = state
        setSignedIn(state == .signedIn)
    }

    public func signIn() { onSignInRequested?() }

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
        case .list, .setup, .signIn: break
        }
    }
}
