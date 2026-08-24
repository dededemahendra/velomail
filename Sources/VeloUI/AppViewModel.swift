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
    public let assistant: AssistantViewModel

    /// AI commands are filtered out when no provider is configured, so the
    /// palette never offers an action that can only fail.
    public var palette: CommandRegistry {
        assistant.isAvailable
            ? CommandRegistry.v1
            : CommandRegistry(commands: CommandRegistry.v1.commands.filter { !$0.action.isAI })
    }

    private let config: AppConfig
    private var keyboard = KeyboardEngine()
    private var isSignedIn: Bool

    public var setupHint: String { AppConfig.setupInstructions }
    public var isConfigured: Bool { config.isConfigured }

    /// Demo mode exists precisely to be looked at without credentials, so it
    /// must reach the mail surface even though it has no client id. Only a
    /// genuinely unconfigured launch goes to setup.
    private var canShowMail: Bool { config.isDemo || (config.isConfigured && isSignedIn) }

    public convenience init(config: AppConfig, store: MailStore, outbound: OutboundService,
                            identity: String, isSignedIn: Bool = false,
                            assistant: MailAssistant = MailAssistant(provider: nil)) {
        self.init(config: config, store: store, outbound: outbound,
                  identity: { identity }, isSignedIn: isSignedIn, assistant: assistant)
    }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService,
                identity: @escaping () -> String, isSignedIn: Bool = false,
                assistant: MailAssistant = MailAssistant(provider: nil)) {
        self.config = config
        self.isSignedIn = isSignedIn
        self.inbox = InboxViewModel(store: store, outbound: outbound)
        self.compose = ComposeViewModel(outbound: outbound, identity: identity)
        self.assistant = AssistantViewModel(assistant: assistant)
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
        // Compose and the palette both own a text field, and while one is open
        // it owns the keyboard. Only Escape gets through, so typing "reply" in
        // the palette cannot fire r=reply and e=archive on the way past.
        if route == .compose || route == .palette {
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

    /// Opens the composer pre-filled with a suggested reply, so a suggestion is
    /// a starting point the user edits rather than something sent on their
    /// behalf.
    public func startReply(with suggestion: String) {
        guard let message = inbox.selectedMessages.last else { return }
        compose.startReply(to: message)
        compose.body = suggestion + compose.body
        assistant.dismiss()
        route = .compose
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
        case .summarizeThread: runAssistant { await $0.summarize(messages: $1) }
        case .suggestReplies: runAssistant { await $0.suggestReplies(to: $1) }
        case .triageThread: runAssistant { await $0.triage(messages: $1) }
        }
    }

    // MARK: - Internals

    private func openSelected() {
        guard inbox.selectedThread != nil else { return }
        // Opening a thread is what marks it read, exactly as in a real client.
        try? inbox.markSelectedRead()
        route = .thread
    }

    /// Runs an assistant operation over the open thread. Silently ignored when
    /// there is no provider or no thread -- both are states, not errors.
    private func runAssistant(_ operation: @escaping (AssistantViewModel, [Message]) async -> Void) {
        guard assistant.isAvailable else { return }
        let messages = inbox.selectedMessages
        guard !messages.isEmpty else { return }
        if route == .palette { route = .list }
        Task { await operation(assistant, messages) }
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
