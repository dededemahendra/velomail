import AppKit
import Combine
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

    /// How a web unsubscribe link is opened. Injected so a test never launches
    /// a browser.
    public var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    public let inbox: InboxViewModel
    public let compose: ComposeViewModel
    public let assistant: AssistantViewModel
    public let search: SearchViewModel
    public let attachments: AttachmentViewModel

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
    /// The inbox is its own `ObservableObject`, and the views observe this one.
    /// Without forwarding, a mark or a star would not appear until something
    /// else — a sync tick — happened to redraw the surface.
    private var inboxChanges: AnyCancellable?

    public var setupHint: String { AppConfig.setupInstructions }
    public var isConfigured: Bool { config.isConfigured }

    /// Demo mode exists precisely to be looked at without credentials, so it
    /// must reach the mail surface even though it has no client id. Only a
    /// genuinely unconfigured launch goes to setup.
    private var canShowMail: Bool { config.isDemo || (config.isConfigured && isSignedIn) }

    public convenience init(config: AppConfig, store: MailStore, outbound: OutboundService,
                            identity: String, isSignedIn: Bool = false,
                            assistant: MailAssistant = MailAssistant(provider: nil),
                            search: SearchViewModel? = nil,
                            snippets: SnippetLibrary = .empty,
                            attachmentModel: AttachmentViewModel? = nil) {
        self.init(config: config, store: store, outbound: outbound,
                  identity: { identity }, isSignedIn: isSignedIn, assistant: assistant,
                  search: search, snippets: snippets, attachmentModel: attachmentModel)
    }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService,
                identity: @escaping () -> String, isSignedIn: Bool = false,
                assistant: MailAssistant = MailAssistant(provider: nil),
                search: SearchViewModel? = nil,
                snippets: SnippetLibrary = .empty,
                attachmentModel: AttachmentViewModel? = nil) {
        self.config = config
        self.isSignedIn = isSignedIn
        self.inbox = InboxViewModel(store: store, outbound: outbound)
        self.compose = ComposeViewModel(outbound: outbound, identity: identity, library: snippets)
        self.outbound = outbound
        self.followUp = FollowUpService(store)
        self.resolveIdentity = identity
        self.assistant = AssistantViewModel(assistant: assistant)
        // Without a source, saving fails with "not available" rather than
        // pretending to work.
        self.attachments = attachmentModel
            ?? AttachmentViewModel(service: AttachmentService(source: UnavailableSource()))
        self.search = search ?? SearchViewModel(
            search: SearchService(store.database),
            translator: QueryTranslator(assistant: assistant))
        self.route = .setup
        self.route = landingRoute
        self.inboxChanges = inbox.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// The inbox, grouped. Derived from the rows the list already holds, so
    /// there is no second query and nothing to keep in sync.
    public var sections: [ThreadSection] { inbox.sections }

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
        case .unsubscribe: unsubscribeSelected()
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
        holdUndo(queued)
        route = .list
        try? inbox.reload()
    }

    /// Opens the undo window on a queued send. Held back briefly so it can be
    /// taken back: there is no unsending mail, and a visible window is the
    /// honest version of "undo send".
    ///
    /// Shared by compose and unsubscribe so the two cannot drift on how long
    /// the promise lasts.
    private func holdUndo(_ queued: Int64) {
        undoableSend = queued
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppViewModel.undoWindow * 1_000_000_000))
            await MainActor.run { self?.expireUndo(queued) }
        }
    }

    /// Acts on the open thread's `List-Unsubscribe`, sending the mailto the
    /// sender declared or opening their web link.
    ///
    /// It deliberately does **not** archive. Unsubscribing and archiving are
    /// different decisions -- you often want off the list and still want to read
    /// this issue -- and coupling them would make `Cmd+Z` ambiguous about which
    /// half it takes back.
    public func unsubscribeSelected() {
        // The newest message whose header *parses*, not merely the newest that
        // has one: the thread view offers the button when any message parses,
        // and a button that appears and does nothing is worse than none.
        // `selectedMessages` is oldest first, hence the reverse.
        guard let link = inbox.selectedMessages.reversed().lazy
            .compactMap({ Unsubscribe.preferred(in: $0.listUnsubscribe ?? "") })
            .first else { return }
        switch link {
        case .mailto:
            guard let draft = Unsubscribe.draft(for: link),
                  let queued = try? outbound.send(draft, after: AppViewModel.undoWindow)
            else { return }
            holdUndo(queued)
        case let .web(url):
            openURL(url)
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
        let targets = inbox.targetThreads
        guard !targets.isEmpty else { return }
        // One wake time for the whole gesture, so a bulk snooze comes back
        // together rather than trickling in.
        let wake = Date().addingTimeInterval(hours * 3_600)
        for thread in targets { try? outbound.snooze(threadID: thread.id, until: wake) }
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


/// Stands in when no Gmail source is wired (demo, or signed out). Saving fails
/// honestly instead of writing an empty file.
struct UnavailableSource: GmailReading {
    func getProfile() async throws -> GmailProfile { throw AttachmentError.unavailable }
    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        throw AttachmentError.unavailable
    }
    func getMessage(id: String) async throws -> GmailMessageDTO { throw AttachmentError.unavailable }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        throw AttachmentError.unavailable
    }
}
