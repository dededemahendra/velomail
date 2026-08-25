import Foundation
import SwiftUI
import VeloCore

public enum Route: Equatable, Sendable {
    case setup, signIn, list, thread, compose, palette, search
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
    public let search: SearchViewModel

    /// The still-cancellable send, if any. Drives the undo banner.
    @Published public private(set) var undoableSend: Int64?
    /// Threads you are waiting on, shown by `g f`.
    @Published public private(set) var followUps: [MailThread] = []
    @Published public private(set) var isShowingFollowUps = false

    /// AI commands are filtered out when no provider is configured, so the
    /// palette never offers an action that can only fail.
    public var palette: CommandRegistry {
        assistant.isAvailable
            ? CommandRegistry.v1
            : CommandRegistry(commands: CommandRegistry.v1.commands.filter { !$0.action.isAI })
    }

    private let config: AppConfig
    private let outbound: OutboundService
    private let followUp: FollowUpService
    private let resolveIdentity: () -> String
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
                            assistant: MailAssistant = MailAssistant(provider: nil),
                            search: SearchViewModel? = nil) {
        self.init(config: config, store: store, outbound: outbound,
                  identity: { identity }, isSignedIn: isSignedIn, assistant: assistant,
                  search: search)
    }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService,
                identity: @escaping () -> String, isSignedIn: Bool = false,
                assistant: MailAssistant = MailAssistant(provider: nil),
                search: SearchViewModel? = nil) {
        self.config = config
        self.isSignedIn = isSignedIn
        self.inbox = InboxViewModel(store: store, outbound: outbound)
        self.compose = ComposeViewModel(outbound: outbound, identity: identity)
        self.outbound = outbound
        self.followUp = FollowUpService(store)
        self.resolveIdentity = identity
        self.assistant = AssistantViewModel(assistant: assistant)
        self.search = search ?? SearchViewModel(
            search: SearchService(store.database),
            translator: QueryTranslator(assistant: assistant))
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
        if route == .compose || route == .palette || route == .search {
            guard input.key == .escape else { return false }
            // Via goBack, not a direct assignment: leaving a surface may have
            // cleanup to do (search clears its query), and bypassing it left
            // the old results behind.
            goBack()
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

    /// Opens a search hit. The thread may not be in the inbox at all, so the
    /// list is reloaded and the selection moved to it rather than assuming it
    /// is already on screen.
    public func openFromSearch(_ thread: MailThread) {
        search.clear()
        try? inbox.reload()
        if let index = inbox.threads.firstIndex(where: { $0.id == thread.id }) {
            inbox.select(index: index)
            route = .thread
        } else {
            // Archived or otherwise outside the inbox: nothing to select, so
            // returning to the list is the honest outcome.
            route = .list
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
        case .openSearch: route = .search
        case .toggleStar: try? inbox.toggleStarSelected()
        case .toggleMark: inbox.toggleMark()
        case .snoozeSelected: snoozeSelected(hours: 4)
        case .undoSend: undoLastSend()
        case .showFollowUps: loadFollowUps()
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
        guard let queued = try? compose.send() else { return }
        // Held back briefly so it can be taken back. There is no unsending
        // mail; a visible window is the honest version of "undo send".
        undoableSend = queued
        route = .list
        try? inbox.reload()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppViewModel.undoWindow * 1_000_000_000))
            await MainActor.run { self?.expireUndo(queued) }
        }
    }

    /// How long a send can be taken back.
    public static let undoWindow: TimeInterval = 10

    public func undoLastSend() {
        guard let id = undoableSend else { return }
        try? outbound.cancelSend(mutationID: id)
        undoableSend = nil
        try? inbox.reload()
    }

    /// Clears the banner only if it still refers to *this* send; a newer one
    /// must not have its window cut short.
    private func expireUndo(_ id: Int64) {
        if undoableSend == id { undoableSend = nil }
    }

    public func snoozeSelected(hours: Double) {
        guard let thread = inbox.selectedThread else { return }
        try? outbound.snooze(threadID: thread.id, until: Date().addingTimeInterval(hours * 3_600))
        try? inbox.reload()
    }

    public func loadFollowUps() {
        followUps = (try? followUp.awaitingReply(identity: resolveIdentity(),
                                                 after: AppViewModel.followUpWindow)) ?? []
        isShowingFollowUps = true
    }

    public func hideFollowUps() { isShowingFollowUps = false }

    /// How long silence counts as needing a nudge.
    public static let followUpWindow: TimeInterval = 3 * 86_400

    /// Escape backs out one level; from the list it does nothing, because there
    /// is nowhere further to go.
    private func goBack() {
        switch route {
        case .thread, .compose, .palette: route = .list
        case .search:
            search.clear()
            route = .list
        case .list, .setup, .signIn: break
        }
    }
}
