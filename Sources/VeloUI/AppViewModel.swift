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
    /// The undo window, start to finish. Published so the banner can show how
    /// much of it is left rather than making the reader guess.
    ///
    /// The whole interval rather than only its end, because the bar needs to
    /// know how much time there was as well as how much remains -- and because
    /// a start read from the clock at render time is a start that moves.
    @Published public private(set) var undoInterval: ClosedRange<Date>?

    /// When the offer runs out.
    public var undoDeadline: Date? { undoInterval?.upperBound }

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
            /// Threads whose unread state to restore. Bulk marking cleared
            /// forty at once with no way back, where archiving one had one.
            case markedRead([String])
            /// Threads to take back out of spam.
            case spam([String])
        }
        public let kind: Kind
        public let prompt: String

        public var symbol: String {
            if case .send = kind { return "paperplane.fill" }
            return "arrow.uturn.backward"
        }

        /// Every thread this offer would touch, for a caller that needs to
        /// know whether an offer is worth making at all.
        public var threadIDs: [String] {
            switch kind {
            case .send: return []
            case let .disposal(ids), let .markedRead(ids), let .spam(ids): return ids
            }
        }
    }

    /// Fetches the next page of older mail, reporting how many arrived. Nil
    /// when there is no account to fetch from.
    private let loadOlder: (@Sendable (Int) async throws -> Int)?
    /// Asks the engine for a pass right now. The loop backs off further after
    /// every failure, so without this a bad afternoon leaves the only way to
    /// try again being to quit the app.
    private let syncNow: (@Sendable () async throws -> Void)?
    /// Where a rule filed from the Senders screen is written. Injectable so a
    /// test cannot write to the reader's real `~/.config/velomail/rules.json`.
    private let settingsStore: SettingsStore

    /// How many older messages one press asks for. The same page the first
    /// sync takes, so the wait is one the writer has already seen.
    public static let olderPageSize = 500

    /// A one-line answer to something the writer just did. Not an error
    /// channel: silence after pressing a button reads as a broken button.
    @Published public private(set) var notice: String?
    /// The last few commands run from the palette, newest first, so what you
    /// keep reaching for stops being fifty rows down.
    @Published public private(set) var recentCommands: [MailAction] = []
    /// How long a passing message stays up. Long enough to read one short
    /// sentence, short enough that it is gone before it becomes furniture.
    /// Settable so a four-second wait is not four seconds of test.
    var noticeWindow: TimeInterval = 4
    /// Identifies the notice a countdown belongs to, so two identical messages
    /// in a row do not have the second cut short by the first one's timer.
    private var noticeToken = 0

    /// How a timed dismissal waits before firing.
    ///
    /// Injected so a test can drive the countdown rather than sleep against
    /// it. Waiting out a real timer means racing it: a notice window of 50ms
    /// and a test that sleeps 200ms looks like a wide margin, and under a
    /// loaded scheduler the sleep still loses -- one parallel run in three.
    /// A test that can only pass serially is a test whose timing assumptions
    /// are unstated.
    typealias DelayedWork = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

    var afterDelay: DelayedWork = { seconds, body in
        let nanoseconds = UInt64(seconds > 0 ? seconds * 1_000_000_000 : 0)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            body()
        }
    }

    /// True when every message's pictures load without being asked for.
    @Published public private(set) var alwaysLoadsImages = false
    /// The choices the app makes on the reader's behalf. Read at the moment
    /// each is used, so changing one in settings takes effect immediately
    /// rather than at the next launch.
    public let preferences: AppPreferences

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
        let base = assistant.isAvailable
            ? CommandRegistry.v1.commands
            : CommandRegistry.v1.commands.filter { !$0.action.isAI }
        // One per account that is not the one already open, plus a way to add
        // another. Same reasoning as labels: no fixed key can name a thing the
        // app learns about at runtime.
        let perAccount = accounts.filter { $0.id != currentAccount }.map {
            Command(title: "Switch to \($0.displayName)", action: .switchAccount, argument: $0.id)
        } + [Command(title: "Add another account", action: .addAccount)]
        // Unfiling is offered for the label being looked at and no other:
        // "Remove from Promotions" while reading Clients is a command for a
        // thread that is not on screen.
        let unfile: [Command]
        if case let .label(id, name) = inbox.scope {
            unfile = [Command(title: "Remove from \(name)", action: .unfileFromLabel, argument: id)]
        } else {
            unfile = []
        }
        // One pair per label, built from what the account actually has. The
        // palette is where a keyboard-first client puts what cannot have a key
        // of its own, and labels are the clearest case of that.
        let perLabel = labels.flatMap { label in
            [Command(title: "Go to \(label.displayName)"
                     + AppViewModel.waiting(unreadCount(in: .label(label.id, label.displayName))),
                     action: .goToLabel, argument: label.id),
             Command(title: "File in \(label.displayName)", action: .fileInLabel, argument: label.id)]
        }
        // The fixed commands, with a count on the ones it means something for.
        let counted = base.map { command -> Command in
            guard let scope = AppViewModel.scope(forGoTo: command.action) else { return command }
            return Command(title: command.title + AppViewModel.waiting(unreadCount(in: scope)),
                           action: command.action, argument: command.argument)
        }
        return CommandRegistry(commands: counted + perAccount + unfile + perLabel)
    }

    /// The mailboxes the app knows about, and which one is open. Set by the
    /// host: the view model has no idea how an account is assembled.
    @Published public var accounts: [Account] = []
    @Published public var currentAccount: String = Account.primaryID
    public var onSwitchAccount: ((String) -> Void)?
    public var onAddAccount: (() -> Void)?

    /// True while the settings window is up. A window rather than a route: it
    /// is about the app rather than about the mail, and closing it should put
    /// the reader back exactly where they were.
    @Published public var isShowingSettings = false
    /// The keymap on a card. A sheet like Settings rather than a route: it is
    /// something you glance at beside your mail, not somewhere you go.
    @Published public var isShowingShortcuts = false
    /// Who is filling the inbox, newest count first. Empty until asked for.
    @Published public private(set) var senders: [SenderSummary] = []
    @Published public var isShowingSenders = false
    /// Which sender row is open, so its actions are on screen.
    @Published public var selectedSender: Int?

    /// Something worth asking about before this message goes. Nothing has been
    /// queued while it is set: the writer can still fix it.
    @Published public private(set) var sendWarning: SendWarning?

    /// A time being asked for. Nothing happens to the mail while this is set:
    /// the writer can still change their mind.
    @Published public private(set) var timeRequest: TimeRequest?

    public struct TimeRequest: Equatable, Identifiable {
        public var id: String { "\(purpose)-\(suggested.timeIntervalSince1970)" }
        public enum Purpose: Equatable { case snooze, send }
        public let purpose: Purpose
        /// Where the picker starts. Not now: every value worth choosing is in
        /// the future, and starting in the past means every use begins by
        /// fixing it.
        public let suggested: Date

        public var title: String {
            switch purpose {
            case .snooze: return "Snooze until"
            case .send: return "Send at"
            }
        }
    }

    /// The labels worth offering, refreshed when the mail is.
    @Published public private(set) var labels: [MailLabel] = []

    /// Runs a palette command, which may carry what it is about.
    public func run(_ command: Command) {
        // Before the switch, so a command that changes route still counts. Only
        // from the palette: keystrokes are already fast, and folding them in
        // would fill Recent with j and k.
        recentCommands = CommandRegistry.remember(command.action, in: recentCommands)
        preferences.recentCommands = recentCommands.map(\.rawValue)
        switch command.action {
        case .goToLabel:
            command.argument.flatMap(label(withID:)).map { show(label: $0) }
        case .fileInLabel:
            command.argument.flatMap(label(withID:)).map { applyLabel($0) }
        case .unfileFromLabel:
            command.argument.flatMap(label(withID:)).map { removeLabel($0) }
        case .switchAccount:
            command.argument.map { onSwitchAccount?($0) }
        case .addAccount:
            onAddAccount?()
        case .openSettings:
            isShowingSettings = true
        case .snoozeAtTime, .sendAtTime:
            perform(command.action)
        default:
            perform(command.action)
        }
    }

    private func label(withID id: String) -> MailLabel? {
        labels.first { $0.id == id }
    }

    /// Opens a label as its own list.
    public func show(label: MailLabel) {
        try? inbox.show(.label(label.id, label.displayName))
        route = .list
    }

    /// Files the selected threads under a label. Undoable like an archive:
    /// they leave the list either way.
    public func applyLabel(_ label: MailLabel) {
        dispose("Filed") {
            for id in inbox.targetThreadIDs {
                try outbound.addLabel(label.id, toThread: id)
            }
            try inbox.reload()
        }
    }

    /// Takes a label off the selected threads. Offered only while looking at
    /// that label, so the thread visibly leaves the list it was in.
    public func removeLabel(_ label: MailLabel) {
        dispose("Unfiled") {
            for id in inbox.targetThreadIDs {
                try outbound.removeLabel(label.id, fromThread: id)
            }
            try inbox.reload()
        }
    }

    /// How much is waiting in a list, so it does not have to be visited to
    /// find out whether it is worth visiting.
    ///
    /// Zero while focused. Focus exists to stop the app saying how much is
    /// waiting, and a number beside every list would be exactly that.
    public func unreadCount(in scope: MailScope) -> Int {
        guard !isFocused else { return 0 }
        switch scope {
        case .inbox:
            return (try? store.unreadInboxCount(
                includingEveryCategory: preferences.countsEveryCategory)) ?? 0
        case .starred: return (try? store.unreadCount(withLabel: "STARRED")) ?? 0
        case let .label(id, _): return (try? store.unreadCount(withLabel: id)) ?? 0
        // Sent, snoozed and archive are places you put things rather than
        // places things arrive, so a count there answers nothing.
        case .sent, .snoozed, .archive: return 0
        }
    }

    private func refreshLabels() {
        labels = (try? store.browsableLabels()) ?? []
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
                            drafts: DraftStore? = nil,
                            loadOlder: (@Sendable (Int) async throws -> Int)? = nil,
                            syncNow: (@Sendable () async throws -> Void)? = nil,
                            settingsStore: SettingsStore = SettingsStore(),
                            preferences: AppPreferences = AppPreferences()) {
        self.init(config: config, store: store, outbound: outbound,
                  identity: { identity }, isSignedIn: isSignedIn, assistant: assistant,
                  search: search, snippets: snippets, attachmentModel: attachmentModel,
                  drafts: drafts, loadOlder: loadOlder, syncNow: syncNow,
                  settingsStore: settingsStore, preferences: preferences)
    }

    public init(config: AppConfig, store: MailStore, outbound: OutboundService,
                identity: @escaping () -> String, isSignedIn: Bool = false,
                assistant: MailAssistant = MailAssistant(provider: nil),
                search: SearchViewModel? = nil,
                snippets: SnippetLibrary = .empty,
                attachmentModel: AttachmentViewModel? = nil,
                drafts: DraftStore? = nil,
                loadOlder: (@Sendable (Int) async throws -> Int)? = nil,
                syncNow: (@Sendable () async throws -> Void)? = nil,
                settingsStore: SettingsStore = SettingsStore(),
                preferences: AppPreferences = AppPreferences()) {
        self.preferences = preferences
        self.alwaysLoadsImages = preferences.loadsRemoteImages
        // Unknown raw values are dropped rather than failing the whole read: a
        // command removed in a later version must not wipe the rest.
        self.recentCommands = preferences.recentCommands.compactMap(MailAction.init(rawValue:))
        self.loadOlder = loadOlder
        self.syncNow = syncNow
        self.settingsStore = settingsStore
        self.config = config
        self.isSignedIn = isSignedIn
        self.inbox = InboxViewModel(store: store, outbound: outbound, preferences: preferences)
        self.compose = ComposeViewModel(
            outbound: outbound, identity: identity, library: snippets, drafts: drafts,
            // Derived from mail already stored, so completion needs no contacts
            // API and no extra permission on the account.
            contacts: { try? AddressBook.build(from: store, identity: identity()) },
            // Lets a reply picked up again still quote what it is answering.
            parentLookup: { threadID in try? store.messages(inThread: threadID).last },
            attachmentLookup: { (try? store.attachments(forMessage: $0)) ?? [] },
            preferences: preferences)
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
            translator: QueryTranslator(assistant: assistant),
            preferences: preferences)
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
        try openMail()
        openDemoRouteIfRequested()
    }

    /// Everything that only makes sense once there is a mailbox to show.
    ///
    /// Shared with `setSignedIn`, and that is the point. It used to live only
    /// in `start()`, behind a guard that requires being signed in *already* --
    /// and since the Keychain read moved off the main actor so the window could
    /// draw, that guard is false on essentially every launch. The app started
    /// signed out, returned early here, and authorisation landed a moment
    /// later; the inbox reloaded and nothing else did. `labels` stayed empty
    /// for the whole session, so no row carried a label chip, `g l` had nothing
    /// to browse and the palette offered no "Remove from ...". Silently: mail
    /// arrived and the list filled, exactly as if there were no labels.
    private func openMail() throws {
        // Whichever list the reader chose to start on.
        try? inbox.show(AppViewModel.scope(named: preferences.opensAt))
        try inbox.reload()
        refreshFailures()
        refreshLabels()
        alwaysLoadsImages = preferences.loadsRemoteImages
        route = .list
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
        // The whole of it, not just the inbox: signing in after launch is the
        // ordinary path, not an edge case.
        if route == .list { try? openMail() }
    }

    /// Where a fresh launch lands. Order matters: with no credentials there is
    /// nothing to sign in *to*, so setup comes first.
    private var landingRoute: Route {
        if config.isDemo { return .list }
        guard config.isConfigured else { return .setup }
        return isSignedIn ? .list : .signIn
    }

    public func setSyncStatus(_ status: SyncStatus) {
        // Only on a real change. This is polled once a second for the life of
        // the process, and almost every tick carries the status the app already
        // had; assigning anyway repainted the entire view tree on a timer,
        // which is what dragged the thread list back to its selection a second
        // after every scroll.
        if status != syncStatus { syncStatus = status }
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
        // A sheet is on top of the list, not beside it. Without this, j and k
        // moved the hidden cursor and e archived a thread nobody could see.
        if isShowingSenders { return handleSenders(input) }
        if isShowingSettings || isShowingShortcuts {
            guard input.key == .escape else { return false }
            isShowingSettings = false
            isShowingShortcuts = false
            return true
        }

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
        case .reply: startReply(toEveryone: preferences.repliesToEveryone)
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
        case .goToStarred: show(.starred)
        case .loadOlderMail: Task { await loadOlderMail() }
        case .syncNow: Task { await syncMailNow() }
        case .selectAll: inbox.markAll()
        case .markAllRead: markEverythingRead()
        case .reportSpam: reportSpamOnSelected()
        case .openInGmail: openSelectedInGmail()
        case .exportThread: exportSelectedThread()
        case .showShortcuts: isShowingShortcuts = true
        case .showSenders: showSenders()
        case .goToArchive: show(.archive)
        // Reached through `run(_:)`, which knows which label. Landing here
        // means a caller had the action without the label to go with it.
        case .snoozeAtTime:
            timeRequest = TimeRequest(purpose: .snooze, suggested: suggestedTime())
        case .sendAtTime:
            timeRequest = TimeRequest(purpose: .send, suggested: suggestedTime())
        case .openSettings: isShowingSettings = true
        case .goToLabel, .fileInLabel, .unfileFromLabel, .switchAccount, .addAccount: break
        case .goToDrafts: showDrafts()
        case .toggleRemoteImages:
            preferences.loadsRemoteImages.toggle()
            alwaysLoadsImages = preferences.loadsRemoteImages
        case .snoozeUntilTomorrow:
            snoozeSelected(until: { [preferences] in Horizon.tomorrow(hour: preferences.morningHour) })
        case .snoozeUntilNextWeek:
            snoozeSelected(until: { [preferences] in Horizon.nextWeek(hour: preferences.morningHour) })
        case .sendTomorrow: sendLater(Horizon.tomorrow(hour: preferences.morningHour))
        case .sendNextWeek: sendLater(Horizon.nextWeek(hour: preferences.morningHour))
        case .unsnoozeSelected: dispose("Woken") { try inbox.unsnoozeSelected() }
        case .back: goBack()
        case .openCommandPalette: route = .palette
        case .openSearch: route = .search
        case .toggleStar: try? inbox.toggleStarSelected()
        case .toggleMark: inbox.toggleMark()
        case .unsubscribe: unsubscribeSelected()
        case .snoozeSelected: snoozeSelected(hours: preferences.snoozeHours)
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

    /// Runs an assistant operation over the open thread.
    ///
    /// No open thread is a state and stays silent -- you can see that nothing
    /// is selected. No provider is not: the palette hides these commands when
    /// none is configured, but the chords stay bound, and a key that does
    /// nothing at all reads as a broken key rather than as a missing setting.
    private func runAssistant(_ operation: @escaping (AssistantViewModel, [Message]) async -> Void) {
        guard assistant.isAvailable else { return sayAIIsNotSetUp() }
        let messages = inbox.selectedMessages
        guard !messages.isEmpty else { return }
        if route == .palette { route = .list }
        Task { await operation(assistant, messages) }
    }

    /// Asks the assistant what the reply should say.
    public func beginAssistantDraft() {
        guard assistant.isAvailable else { return sayAIIsNotSetUp() }
        guard !inbox.selectedMessages.isEmpty else { return }
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
        // Asked before anything is queued, so cancelling leaves the message
        // exactly as it was for the writer to fix.
        if let warning = SendWarning.check(compose.pendingDraft,
                                           recipientLimit: preferences.recipientLimit),
           warning != .missingAttachment || preferences.warnsAboutAttachments {
            sendWarning = warning
            return
        }
        deliver()
    }

    /// Sends anyway, having been asked.
    public func confirmSend() {
        sendWarning = nil
        deliver()
    }

    /// Goes back to the message rather than sending it.
    public func cancelSend() {
        sendWarning = nil
        route = .compose
    }

    private func deliver() {
        guard let queued = try? compose.send() else { return }
        holdUndo(queued)
        route = .list
        try? inbox.reload()
    }

    /// Queues what is in the composer to go at `moment`.
    ///
    /// No undo banner: an offer to take something back for ten seconds makes no
    /// sense for a message that is not going for a day. It is cancellable for
    /// as long as it waits, from the drafts screen.
    public func sendLater(_ moment: Date) {
        guard (try? compose.send(at: moment)) ?? nil != nil else { return }
        route = .list
        refreshOutgoing()
        try? inbox.reload()
    }

    /// Messages written and waiting for their hour.
    @Published public private(set) var scheduled: [ScheduledSend] = []

    /// Lets one go on the next drain.
    public func sendNow(_ send: ScheduledSend) {
        try? outbound.sendNow(mutationID: send.id)
        refreshOutgoing()
    }

    /// Takes one back out of the queue and puts its words in the composer.
    public func unschedule(_ send: ScheduledSend) {
        guard let draft = (try? outbound.unschedule(mutationID: send.id)) ?? nil else {
            refreshOutgoing()
            return
        }
        compose.resume(draft)
        route = .compose
        refreshOutgoing()
        try? inbox.reload()
    }

    private func refreshOutgoing() {
        scheduled = (try? outbound.scheduled()) ?? []
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
        perform(unsubscribe: link, from: nil)
    }

    /// Acts on a parsed unsubscribe link, whichever screen asked for it.
    ///
    /// The mailto goes through the outbound queue so `Cmd+Z` takes it back; a
    /// web link opens, because there is nothing to take back.
    private func perform(unsubscribe link: UnsubscribeLink, from who: String?) {
        switch link {
        case .mailto:
            guard let draft = Unsubscribe.draft(for: link),
                  let queued = try? outbound.send(draft, after: preferences.undoWindow)
            else { return }
            offerUndo(.init(kind: .send(queued),
                            prompt: who.map { "Unsubscribing from \($0)" } ?? "Message sent"))
        case let .web(url):
            openURL(url)
            if let who { show(notice: "Opened \(who)\u{2019}s unsubscribe page") }
        }
    }

    /// The list a "Go to" command opens, when it opens one.
    static func scope(forGoTo action: MailAction) -> MailScope? {
        switch action {
        case .goToInbox: return .inbox
        case .goToStarred: return .starred
        default: return nil
        }
    }

    /// " (3)", or nothing at all. "Go to Sent (0)" is noise on every list that
    /// happens to be quiet.
    static func waiting(_ count: Int) -> String { count > 0 ? " (\(count))" : "" }

    /// The scope a stored name refers to. Unknown names fall back to the
    /// inbox: a setting written by a newer build should not open nothing.
    static func scope(named name: String) -> MailScope {
        switch name {
        case "sent": return .sent
        case "starred": return .starred
        case "snoozed": return .snoozed
        case "archive": return .archive
        default: return .inbox
        }
    }

    /// Switches which list is on screen and puts the focus back on it.
    private func show(_ scope: MailScope) {
        try? inbox.show(scope)
        route = .list
    }

    /// Acts on the time that was chosen.
    public func confirmTime(_ moment: Date) {
        guard let request = timeRequest else { return }
        timeRequest = nil
        switch request.purpose {
        case .snooze: snoozeSelected(until: { moment })
        case .send:
            // A time that is not meaningfully in the future is an ordinary
            // send, and an ordinary send can be taken back. Scheduling it
            // instead would put it in a "waiting to send" list it leaves a
            // second later, with no undo offered on the way past.
            if moment.timeIntervalSinceNow <= OutboundService.scheduleThreshold {
                perform(.send)
            } else {
                sendLater(moment)
            }
        }
    }

    public func cancelTime() { timeRequest = nil }

    /// Tomorrow morning, unless that is less than an hour away, in which case
    /// an hour from now: a picker that opens on a time already past is a form
    /// to correct rather than a choice to make.
    private func suggestedTime() -> Date {
        let tomorrow = Horizon.tomorrow(hour: preferences.morningHour)
        return tomorrow.timeIntervalSinceNow > 3_600
            ? tomorrow
            : Date().addingTimeInterval(3_600)
    }

    /// Asks for another page of older mail and says what came back.
    public func loadOlderMail() async {
        guard let loadOlder else { return }
        clearNotice()
        do {
            let found = try await loadOlder(AppViewModel.olderPageSize)
            try? inbox.reload()
            show(notice: found == 0
                ? "Nothing older to fetch"
                : "\(found) older message\(found == 1 ? "" : "s")")
        } catch {
            show(notice: "Could not fetch older mail")
        }
    }

    /// Shows a passing message and starts its countdown.
    ///
    /// Notices used to have no lifetime at all: one was cleared only when the
    /// next notice-producing action began, so "Up to date" sat on screen until
    /// the reader happened to sync again.
    private func show(notice text: String) {
        notice = text
        noticeToken += 1
        let token = noticeToken
        afterDelay(noticeWindow) { [weak self] in self?.expireNotice(token) }
    }

    /// Clears the banner only if it is still the one that started this
    /// countdown; a newer message must keep its full window.
    private func expireNotice(_ token: Int) {
        if noticeToken == token { notice = nil }
    }

    private func clearNotice() {
        notice = nil
        noticeToken += 1
    }

    // MARK: - Acting on a banner

    /// Puts the reader on the thread a notification was about.
    ///
    /// The thread may have been archived or trashed on another device between
    /// the banner appearing and the click, so a miss says so rather than
    /// leaving the reader wondering why nothing moved.
    public func openFromNotification(_ threadID: String) {
        // Any sheet or composer is in the way of the thing just asked for.
        isShowingSenders = false
        isShowingSettings = false
        isShowingShortcuts = false
        show(.inbox)
        if !inbox.select(threadID: threadID) {
            show(notice: "That conversation is no longer in the inbox")
        }
    }

    /// Files the thread a notification was about, without opening anything:
    /// the point of Archive on a banner is not having to look at the app.
    public func archiveFromNotification(_ threadID: String) {
        try? outbound.archive(threadID: threadID)
        try? inbox.reload()
        offerUndo(.init(kind: .disposal([threadID]), prompt: "Archived"))
    }

    public func markReadFromNotification(_ threadID: String) {
        try? outbound.markRead(threadID: threadID)
        try? inbox.reload()
    }

    // MARK: - Senders

    /// The keys the Senders sheet answers. Everything else is swallowed rather
    /// than passed down to the list underneath it.
    private func handleSenders(_ input: KeyInput) -> Bool {
        switch input.key {
        case .escape:
            isShowingSenders = false
        case .enter:
            selectedSenderSummary.map { openSenderInInbox($0) }
        case let .character(character):
            switch character {
            case "j": moveSender(by: 1)
            case "k": moveSender(by: -1)
            // The same letters they mean in the list, on the sender instead of
            // the thread.
            case "e": selectedSenderSummary.map { archiveAll(from: $0) }
            case "u": selectedSenderSummary.map { unsubscribe(from: $0) }
            default: break
            }
        default:
            break
        }
        return true
    }

    private var selectedSenderSummary: SenderSummary? {
        selectedSender.flatMap { senders.indices.contains($0) ? senders[$0] : nil }
    }

    private func moveSender(by delta: Int) {
        guard !senders.isEmpty else { return }
        let current = selectedSender ?? 0
        selectedSender = min(max(current + delta, 0), senders.count - 1)
    }

    /// Opens the list of who is filling the inbox.
    public func showSenders() {
        senders = (try? store.inboxSenders()) ?? []
        selectedSender = senders.isEmpty ? nil : 0
        isShowingSenders = true
    }

    /// Archives every inbox thread from one address, in one undoable step.
    public func archiveAll(from sender: SenderSummary) {
        let threads = (try? store.inboxThreads(from: sender.address)) ?? []
        guard !threads.isEmpty else { return }
        for thread in threads { try? outbound.archive(threadID: thread.id) }
        try? inbox.reload()
        refreshSenders()
        // One offer for the whole sweep, not one per thread: four hundred
        // banners would bury the only one that matters.
        offerUndo(.init(kind: .disposal(threads.map(\.id)),
                        prompt: "\(threads.count) archived from \(sender.displayName)"))
    }

    /// Files a rule so this sender's mail archives itself from now on, and
    /// clears what is already here.
    ///
    /// Both halves, because a rule that only applies to future mail leaves the
    /// four hundred already sitting there, which is the reason you opened this
    /// screen.
    public func alwaysArchive(from sender: SenderSummary) {
        let library = settingsStore.rules()
        let rule = MailRule.forSender(sender, doing: [.archive],
                                      named: "Archive \(sender.displayName)",
                                      order: library.rules.count)
        guard !library.rules.contains(where: { $0.id == rule.id }) else {
            show(notice: "Already archiving \(sender.displayName)")
            return
        }
        do {
            try settingsStore.saveRules(RuleLibrary(rules: library.rules + [rule]))
        } catch {
            show(notice: "Could not save the rule")
            return
        }
        archiveAll(from: sender)
    }

    /// Leaves one sender's list, using the newest message that says how.
    public func unsubscribe(from sender: SenderSummary) {
        let threads = (try? store.inboxThreads(from: sender.address)) ?? []
        let link = threads.lazy
            .flatMap { (try? self.store.messages(inThread: $0.id)) ?? [] }
            .sorted { $0.date > $1.date }
            .compactMap { Unsubscribe.preferred(in: $0.listUnsubscribe ?? "") }
            .first
        guard let link else {
            show(notice: "No unsubscribe link on this sender")
            return
        }
        perform(unsubscribe: link, from: sender.displayName)
    }

    /// Closes the screen on the sender's newest thread, so "who is this" and
    /// "what do they actually send" are one step apart.
    public func openSenderInInbox(_ sender: SenderSummary) {
        isShowingSenders = false
        guard let newest = (try? store.inboxThreads(from: sender.address))?.first else { return }
        inbox.select(threadID: newest.id)
    }

    private func refreshSenders() {
        guard isShowingSenders else { return }
        senders = (try? store.inboxSenders()) ?? []
        if let selected = selectedSender, selected >= senders.count {
            selectedSender = senders.isEmpty ? nil : senders.count - 1
        }
    }

    /// Points at the setting rather than leaving the keystroke unanswered.
    private func sayAIIsNotSetUp() {
        show(notice: "AI is not set up. Add a key under Settings \u{203A} AI.")
    }

    /// Clears the unread state of everything in the list at once.
    ///
    /// The whole list, not the marked rows: "mark all as read" that quietly
    /// meant "mark the two rows you ticked" would be a trap.
    private func markEverythingRead() {
        let unread = inbox.threads.filter(\.isUnread)
        guard !unread.isEmpty else {
            show(notice: "Nothing unread here")
            return
        }
        for thread in unread { try? outbound.markRead(threadID: thread.id) }
        try? inbox.reload()
        // Only the ones actually changed, so undo cannot make unread something
        // that was already read before the press.
        offerUndo(.init(kind: .markedRead(unread.map(\.id)),
                        prompt: "\(unread.count) marked read"))
    }

    private func reportSpamOnSelected() {
        let targets = inbox.targetThreads
        guard !targets.isEmpty else { return }
        for thread in targets { try? outbound.reportSpam(threadID: thread.id) }
        try? inbox.reload()
        offerUndo(.init(kind: .spam(targets.map(\.id)),
                        prompt: targets.count == 1
                            ? "Reported as spam"
                            : "\(targets.count) reported as spam"))
    }

    /// Hands the selected thread to Gmail on the web.
    ///
    /// The escape hatch for everything this client does not do -- printing,
    /// filters, the settings Google keeps to itself -- rather than an admission
    /// of defeat on each of them separately.
    private func openSelectedInGmail() {
        guard let thread = inbox.selectedThread else { return }
        guard let url = URL(string: "https://mail.google.com/mail/u/0/#all/\(thread.id)") else { return }
        openURL(url)
    }

    private func exportSelectedThread() {
        guard let thread = inbox.selectedThread else { return }
        let messages = inbox.selectedMessages
        guard !messages.isEmpty else { return }
        let text = ThreadExport.plainText(of: messages)
        let name = ThreadExport.fileName(for: messages, threadID: thread.id)
        do {
            let url = try ThreadExport.write(text, named: name)
            show(notice: "Saved to \(url.lastPathComponent)")
        } catch {
            show(notice: "Could not save the thread")
        }
    }

    /// Asks for a sync pass now rather than waiting out the backoff.
    ///
    /// The engine coalesces a call made while a pass is already in flight, so
    /// pressing this repeatedly is harmless.
    /// Whether fetching by hand is possible at all.
    ///
    /// Demo mode has no account behind it and `syncMailNow` returns
    /// immediately, so the control is left off the screen rather than offered
    /// as a button that does nothing when pressed.
    public var canSyncByHand: Bool { syncNow != nil }

    public func syncMailNow() async {
        guard let syncNow else { return }
        clearNotice()
        do {
            try await syncNow()
            try? inbox.reload()
            show(notice: "Up to date")
        } catch {
            // The status bar carries the detail; this only confirms the press
            // was heard, since a failed pass can leave the list unchanged.
            show(notice: "Could not reach Gmail")
        }
    }

    // MARK: - Drafts

    /// Opens the draft list, always re-read: one written since the last visit
    /// has to be in it.
    public func showDrafts() {
        drafts = compose.storedDrafts
        refreshOutgoing()
        route = .drafts
    }

    /// Puts a chosen draft back in the composer, keeping its row so further
    /// edits update it rather than forking a copy.
    /// Opens the composer on a `mailto:` from a message body.
    ///
    /// In this app's composer rather than the system's idea of a mail client,
    /// which is what handing the URL to `NSWorkspace` did. The query comes with
    /// it: an unsubscribe link is routinely
    /// `mailto:leave@list?subject=unsubscribe`, and a message sent without that
    /// subject does nothing at all.
    public func startMessage(from link: MailtoLink) {
        // A fresh message, not whatever was half-written: following a link is
        // starting something, and silently editing an unrelated draft would
        // send it to the wrong person.
        compose.startNew()
        compose.to = link.to.joined(separator: ", ")
        compose.cc = link.cc.joined(separator: ", ")
        compose.subject = link.subject ?? ""
        compose.body = link.body ?? ""
        route = .compose
    }

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
    ///
    /// Assigned only on a change, for the same reason as `setSyncStatus`: this
    /// runs on the once-a-second status poll, and an empty list replacing an
    /// empty list is not news the view tree needs repainting for.
    public func refreshFailures() {
        let current = (try? outbound.failures(maxAttempts: OutboundService.maxAttempts)) ?? []
        if current != failures { failures = current }
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

    /// How long a send can be taken back, unless the reader has said otherwise.
    /// Kept as the default rather than the value: callers that have an app to
    /// ask should ask it.
    public static let undoWindow: TimeInterval = 10

    /// Takes back whatever was last done, if anything still can be.
    public func undo() {
        guard let undoable else { return }
        switch undoable.kind {
        case let .send(id):
            try? outbound.cancelSend(mutationID: id)
        case let .disposal(threadIDs):
            for threadID in threadIDs { try? outbound.unarchive(threadID: threadID) }
        case let .markedRead(threadIDs):
            for threadID in threadIDs { try? outbound.markUnread(threadID: threadID) }
        case let .spam(threadIDs):
            for threadID in threadIDs { try? outbound.notSpam(threadID: threadID) }
        }
        self.undoable = nil
        undoInterval = nil
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
        let window = preferences.undoWindow
        // The banner offered ten seconds and gave no sign of how many were
        // left, which makes a deliberate wait feel like a gamble.
        let opened = Date()
        undoInterval = opened...opened.addingTimeInterval(window)
        afterDelay(window) { [weak self] in self?.expireUndo(action) }
    }

    /// Clears the banner only if it still refers to *this* action; a newer one
    /// must not have its window cut short.
    private func expireUndo(_ action: Undoable) {
        if undoable == action {
            undoable = nil
            undoInterval = nil
        }
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

    /// How much is actually unread, in the inbox.
    ///
    /// Asked of the store rather than counted off `inbox.threads`, which is
    /// whichever list is on screen: opening Sent, or Starred, or a label
    /// silently rewrote the number on the Dock to that list's unread count.
    public var unreadCount: Int {
        (try? store.unreadInboxCount(
            includingEveryCategory: preferences.countsEveryCategory)) ?? 0
    }

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
