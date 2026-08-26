import AppKit
import Combine
import Foundation
import SwiftUI
import VeloCore

public enum Route: Equatable, Sendable {
    case setup, signIn, list, thread, compose, palette, search, analytics, drafts
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

    /// The one thing that can currently be taken back, if any.
    ///
    /// One slot, not a stack: offering to undo something the user stopped
    /// thinking about two actions ago is worse than offering nothing.
    @Published public private(set) var undoable: Undoable?

    /// What the banner says, or nil when there is nothing to undo.
    public var undoPrompt: String? { undoable?.prompt }

    /// The banner's icon. Carried with the action rather than inferred from the
    /// wording, which would change the icon the next time the copy is edited.
    public var undoSymbol: String? { undoable?.symbol }

    /// Kept for the send path, which needs the queue id to cancel.
    public var undoableSend: Int64? {
        if case let .send(id) = undoable?.kind { return id }
        return nil
    }

    public struct Undoable: Equatable {
        public enum Kind: Equatable {
            case send(Int64)
            /// Threads to put back in the inbox.
            case disposal([String])
        }
        public let kind: Kind
        public let prompt: String

        public var symbol: String {
            if case .send = kind { return "paperplane.fill" }
            return "arrow.uturn.backward"
        }
    }

    /// Every message being written, most recently touched first.
    @Published public private(set) var drafts: [StoredDraft] = []

    /// Changes the queue gave up on. Unlike undo this does not expire: a
    /// message that never went has to still be there when the writer looks up.
    @Published public private(set) var failures: [MailFailure] = []

    /// One line for the banner, or nil when nothing has failed.
    ///
    /// Always names a single failure, even when several are waiting: a bulk
    /// "dismiss all" over two failed sends would throw away both drafts on one
    /// click. They are stepped through instead.
    public var failurePrompt: String? { failures.first?.summary }

    /// How many failures are queued behind the one on show.
    public var failureOverflow: Int { max(0, failures.count - 1) }

    /// Threads you are waiting on, shown by `g f`.
    @Published public private(set) var followUps: [MailThread] = []
    @Published public private(set) var isShowingFollowUps = false
    /// Suppresses banners and hides how much is waiting.
    @Published public private(set) var isFocused = false
    @Published public private(set) var analytics: MailAnalytics.Report?

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
    private let store: MailStore
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
                            attachmentModel: AttachmentViewModel? = nil,
                            drafts: DraftStore? = nil) {
        self.init(config: config, store: store, outbound: outbound,
                  identity: { identity }, isSignedIn: isSignedIn, assistant: assistant,
                  search: search, snippets: snippets, attachmentModel: attachmentModel,
                  drafts: drafts)
    }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService,
                identity: @escaping () -> String, isSignedIn: Bool = false,
                assistant: MailAssistant = MailAssistant(provider: nil),
                search: SearchViewModel? = nil,
                snippets: SnippetLibrary = .empty,
                attachmentModel: AttachmentViewModel? = nil,
                drafts: DraftStore? = nil) {
        self.config = config
        self.isSignedIn = isSignedIn
        self.inbox = InboxViewModel(store: store, outbound: outbound)
        self.compose = ComposeViewModel(
            outbound: outbound, identity: identity, library: snippets, drafts: drafts,
            // Derived from mail already stored, so completion needs no contacts
            // API and no extra permission on the account.
            contacts: { try? AddressBook.build(from: store, identity: identity()) })
        self.outbound = outbound
        self.followUp = FollowUpService(store)
        self.store = store
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
        refreshFailures()
        route = .list
        openDemoRouteIfRequested()
    }

    /// Opens a named surface on a demo launch, so every screen can be reviewed
    /// without synthetic input. Ignored entirely outside demo, and an
    /// unrecognised name is ignored rather than failing.
    private func openDemoRouteIfRequested() {
        guard config.isDemo, let requested = config.demoRoute else { return }
        switch requested {
        case "compose":
            compose.startNew()
            route = .compose
        case "search":
            route = .search
        case "palette":
            route = .palette
        case "thread":
            perform(.openSelected)
        case "analytics":
            showAnalytics()
        case "draft":
            beginAssistantDraft()
        default:
            break
        }
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

    public func setSyncStatus(_ status: SyncStatus) {
        syncStatus = status
        // A push gives up during a sync, so this is the moment the answer
        // changes. Polling for it on a timer would only ever be late.
        refreshFailures()
    }

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
        case .archiveSelected: dispose("Archived") { try inbox.archiveSelected() }
        case .trashSelected: dispose("Deleted") { try inbox.trashSelected() }
        case .markUnreadSelected: try? inbox.markSelectedUnread()
        case .reply: startReply()
        case .replyAll: startReply(toEveryone: true)
        case .forward: startForward()
        case .compose:
            compose.startNew()
            // Resuming is what someone expects on reopening the app after being
            // interrupted; a blank window would silently discard their work.
            compose.resumeDraft()
            route = .compose
        case .send: send()
        case .goToInbox: show(.inbox)
        case .goToSent: show(.sent)
        case .goToSnoozed: show(.snoozed)
        case .goToDrafts: showDrafts()
        case .snoozeUntilTomorrow: snoozeSelected(until: { SnoozeHorizon.tomorrow() })
        case .snoozeUntilNextWeek: snoozeSelected(until: { SnoozeHorizon.nextWeek() })
        case .unsnoozeSelected: dispose("Woken") { try inbox.unsnoozeSelected() }
        case .back: goBack()
        case .openCommandPalette: route = .palette
        case .openSearch: route = .search
        case .toggleStar: try? inbox.toggleStarSelected()
        case .toggleMark: inbox.toggleMark()
        case .unsubscribe: unsubscribeSelected()
        case .snoozeSelected: snoozeSelected(hours: 4)
        case .undo: undo()
        case .showFollowUps: loadFollowUps()
        case .toggleFocus: toggleFocus()
        case .discardDraft: compose.discardDraft()
        case .showAnalytics: showAnalytics()
        case .summarizeThread: runAssistant { await $0.summarize(messages: $1) }
        case .suggestReplies: runAssistant { await $0.suggestReplies(to: $1) }
        case .draftReplyWithAI: beginAssistantDraft()
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

    /// Asks the assistant what the reply should say. Silently ignored without a
    /// provider or an open thread -- both are states, not errors.
    public func beginAssistantDraft() {
        guard assistant.isAvailable, !inbox.selectedMessages.isEmpty else { return }
        if route == .palette { route = .list }
        assistant.beginDraft()
    }

    /// Runs the drafting the panel's field asked for.
    public func runAssistantDraft() {
        let messages = inbox.selectedMessages
        guard !messages.isEmpty else { return }
        Task { await assistant.runDraft(messages: messages) }
    }

    private func startReply(toEveryone: Bool = false) {
        guard let message = inbox.selectedMessages.last else { return }
        if toEveryone {
            compose.startReplyAll(to: message)
        } else {
            compose.startReply(to: message)
        }
        route = .compose
    }

    /// Forwards the open message, carrying its files -- forwarding an invoice
    /// without the invoice is useless.
    private func startForward() {
        guard let message = inbox.selectedMessages.last else { return }
        let files = inbox.attachments(forMessage: message.id).compactMap { attachment -> DraftAttachment? in
            guard let inline = attachment.inlineData,
                  let data = AttachmentService.decodeBase64URL(inline) else { return nil }
            return DraftAttachment(filename: attachment.filename,
                                   mimeType: attachment.mimeType, data: data)
        }
        compose.startForward(of: message, attachments: files)
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
        offerUndo(.init(kind: .send(queued), prompt: "Message sent"))
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

    /// Switches which list is on screen and puts the focus back on it.
    private func show(_ scope: MailScope) {
        try? inbox.show(scope)
        route = .list
    }

    // MARK: - Drafts

    /// Opens the draft list, always re-read: one written since the last visit
    /// has to be in it.
    public func showDrafts() {
        drafts = compose.storedDrafts
        route = .drafts
    }

    /// Puts a chosen draft back in the composer, keeping its row so further
    /// edits update it rather than forking a copy.
    public func resumeDraft(_ stored: StoredDraft) {
        compose.resume(stored)
        route = .compose
    }

    /// Bins one draft from the list, leaving the rest and whatever is being
    /// written alone.
    public func discardDraft(_ stored: StoredDraft) {
        compose.discard(stored)
        drafts = compose.storedDrafts
    }

    // MARK: - Failures

    /// Rereads what the queue has given up on.
    public func refreshFailures() {
        failures = (try? outbound.failures(maxAttempts: OutboundService.maxAttempts)) ?? []
    }

    /// Puts a failed send's words back in the composer, where they can be
    /// fixed and sent again through the ordinary path.
    public func reopenFailure(_ failure: MailFailure) {
        guard let draft = (try? outbound.reopen(mutationID: failure.id)) ?? nil else {
            dismissFailure(failure)
            return
        }
        compose.resume(draft)
        route = .compose
        refreshFailures()
    }

    /// Accepts a failure and stops showing it. The local side was already put
    /// back when the push failed, so there is nothing else to undo.
    public func dismissFailure(_ failure: MailFailure) {
        try? outbound.dismiss(mutationID: failure.id)
        refreshFailures()
    }

    /// How long a send can be taken back.
    public static let undoWindow: TimeInterval = 10

    /// Takes back whatever was last done, if anything still can be.
    public func undo() {
        guard let undoable else { return }
        switch undoable.kind {
        case let .send(id):
            try? outbound.cancelSend(mutationID: id)
        case let .disposal(threadIDs):
            for threadID in threadIDs { try? outbound.unarchive(threadID: threadID) }
        }
        self.undoable = nil
        try? inbox.reload()
    }

    /// Runs a disposal and remembers what it removed, so it can be put back.
    ///
    /// The ids are captured *before* the action, because afterwards the threads
    /// are gone from the list and there is nothing left to name.
    private func dispose(_ prompt: String, _ action: () throws -> Void) {
        let affected = inbox.targetThreadIDs
        guard !affected.isEmpty, (try? action()) != nil else { return }
        offerUndo(.init(kind: .disposal(affected), prompt: prompt))
    }

    /// Shows the banner and starts its countdown.
    private func offerUndo(_ action: Undoable) {
        undoable = action
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AppViewModel.undoWindow * 1_000_000_000))
            await MainActor.run { self?.expireUndo(action) }
        }
    }

    /// Clears the banner only if it still refers to *this* action; a newer one
    /// must not have its window cut short.
    private func expireUndo(_ action: Undoable) {
        if undoable == action { undoable = nil }
    }

    public func snoozeSelected(hours: Double) {
        snoozeSelected(until: { Date().addingTimeInterval(hours * 3_600) })
    }

    /// Snoozes every target to one wake time, so a bulk snooze comes back
    /// together rather than trickling in.
    ///
    /// Undoable like an archive: the thread leaves the list either way, and a
    /// mistyped `h` should cost no more than a mistyped `e`.
    public func snoozeSelected(until horizon: () -> Date) {
        let wake = horizon()
        dispose("Snoozed") {
            let targets = inbox.targetThreads
            guard !targets.isEmpty else { return }
            for thread in targets { try outbound.snooze(threadID: thread.id, until: wake) }
            try inbox.reload()
        }
    }

    public func loadFollowUps() {
        followUps = (try? followUp.awaitingReply(identity: resolveIdentity(),
                                                 after: AppViewModel.followUpWindow)) ?? []
        isShowingFollowUps = true
    }

    public func hideFollowUps() { isShowingFollowUps = false }

    /// Derived on demand rather than kept up to date: there is nothing stored
    /// to go stale, and the numbers are always exactly the mailbox.
    public func showAnalytics() {
        analytics = try? MailAnalytics(store).report(identity: resolveIdentity())
        route = .analytics
    }

    // MARK: - Attention

    /// How much is actually unread.
    public var unreadCount: Int { inbox.threads.filter(\.isUnread).count }

    /// What the badge shows. Focus hides the number rather than the mail --
    /// not knowing how much is waiting is the point of it.
    public var visibleUnreadCount: Int { isFocused ? 0 : unreadCount }

    public var shouldAnnounce: Bool { !isFocused }

    public func toggleFocus() { isFocused.toggle() }

    /// The account's own address, for filtering self-authored mail out of
    /// notifications.
    public var identity: String { resolveIdentity() }

    /// How long silence counts as needing a nudge.
    public static let followUpWindow: TimeInterval = 3 * 86_400

    /// Escape backs out one level; from the list it does nothing, because there
    /// is nowhere further to go.
    private func goBack() {
        switch route {
        case .thread, .compose, .palette, .analytics, .drafts: route = .list
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
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        throw AttachmentError.unavailable
    }
    func getMessage(id: String) async throws -> GmailMessageDTO { throw AttachmentError.unavailable }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        throw AttachmentError.unavailable
    }
}
