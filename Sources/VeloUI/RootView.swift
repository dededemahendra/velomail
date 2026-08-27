import SwiftUI
import VeloCore


/// Routes to whichever surface the app state says is focused, and hosts the
/// single key monitor that drives the whole app.
public struct RootView: View {
    /// Built once and kept: reopening settings should show what was typed last
    /// time, not a fresh read of files that have not changed.
    @StateObject private var settings = SettingsViewModel()

    @ObservedObject var app: AppViewModel

    public init(app: AppViewModel) { self.app = app }

    public var body: some View {
        Group {
            switch app.route {
            case .setup:
                SetupView(clientIDHint: app.setupHint)
            case .signIn:
                SignInView(state: app.authState, onSignIn: app.signIn)
            case .analytics:
                AnalyticsView(report: app.analytics, onClose: { app.perform(.back) })
            case .search:
                SearchView(model: app.search,
                           isAIEnabled: app.assistant.isAvailable,
                           onOpen: { app.openFromSearch($0) },
                           onCancel: { app.perform(.back) })
            case .compose:
                ComposeView(model: app.compose,
                            assistant: app.assistant,
                            onSend: { app.perform(.send) },
                            onSendLater: { app.sendLater($0) },
                            onCancel: { app.perform(.back) })
            case .drafts:
                DraftListView(drafts: app.drafts,
                              scheduled: app.scheduled,
                              onOpen: { app.resumeDraft($0) },
                              onDiscard: { app.discardDraft($0) },
                              onSendNow: { app.sendNow($0) },
                              onUnschedule: { app.unschedule($0) },
                              onClose: { app.perform(.back) })
            default:
                mailSurface
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                // Above undo, because it is the one that does not expire.
                if let failure = app.failurePrompt {
                    FailureBanner(prompt: failure,
                                  canReopen: app.failures.first?.draft != nil,
                                  overflow: app.failureOverflow,
                                  onReopen: { app.failures.first.map { app.reopenFailure($0) } },
                                  onDismiss: { app.failures.first.map { app.dismissFailure($0) } })
                }
                if let notice = app.notice {
                    NoticeBanner(text: notice)
                }
                if let prompt = app.undoPrompt {
                    UndoBanner(prompt: prompt, symbol: app.undoSymbol ?? "arrow.uturn.backward",
                               deadline: app.undoDeadline,
                               onUndo: { app.undo() })
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.undoPrompt)
        .animation(.easeOut(duration: 0.18), value: app.failurePrompt)
        .animation(.easeOut(duration: 0.18), value: app.notice)
        .alert("Send this message?", isPresented: Binding(
            get: { app.sendWarning != nil },
            set: { if !$0 { app.cancelSend() } })) {
            Button(app.sendWarning?.proceed ?? "Send") { app.confirmSend() }
            Button("Cancel", role: .cancel) { app.cancelSend() }
        } message: {
            Text(app.sendWarning?.question ?? "")
        }
        .sheet(item: Binding(get: { app.timeRequest }, set: { if $0 == nil { app.cancelTime() } })) {
            request in
            TimePickerSheet(request: request,
                            morningHour: app.preferences.morningHour,
                            onConfirm: { app.confirmTime($0) },
                            onCancel: { app.cancelTime() })
        }
        .sheet(isPresented: $app.isShowingSenders) {
            SendersView(senders: app.senders,
                        totalThreads: app.senders.reduce(0) { $0 + $1.threads },
                        selected: app.selectedSender,
                        onSelect: { app.selectedSender = $0 },
                        onArchiveAll: { app.archiveAll(from: $0) },
                        onAlwaysArchive: { app.alwaysArchive(from: $0) },
                        onUnsubscribe: { app.unsubscribe(from: $0) },
                        onOpen: { app.openSenderInInbox($0) },
                        onClose: { app.isShowingSenders = false })
        }
        .sheet(isPresented: $app.isShowingShortcuts) {
            ShortcutsView(onClose: { app.isShowingShortcuts = false })
        }
        .sheet(isPresented: $app.isShowingSettings) {
            SettingsView(model: settings,
                         accounts: app.accounts,
                         currentAccount: app.currentAccount,
                         onSwitchAccount: {
                             app.isShowingSettings = false
                             app.onSwitchAccount?($0)
                         },
                         onAddAccount: {
                             app.isShowingSettings = false
                             app.onAddAccount?()
                         },
                         onClose: { app.isShowingSettings = false })
        }
        .overlay(alignment: .top) {
            if app.route == .palette {
                CommandPaletteView(registry: app.palette,
                                   recents: app.recentCommands,
                                   onRun: { app.run($0) },
                                   onCancel: { app.perform(.back) })
                    .padding(.top, 90)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(KeyMonitor { app.handle($0) })
    }

    /// List and thread live side by side; opening a thread just moves focus,
    /// so the list never has to be rebuilt.
    private var mailSurface: some View {
        HSplitView {
            VStack(spacing: 0) {
                if app.isShowingFollowUps {
                    FollowUpBar(threads: app.followUps,
                                onDismiss: { app.hideFollowUps() },
                                onOpen: { app.openFromSearch($0) })
                    Divider()
                }
                MailboxHeader(title: app.inbox.title, count: app.inbox.threads.count,
                              unread: app.unreadCount(in: app.inbox.scope))
                Divider()
                if app.inbox.threads.isEmpty {
                    EmptyListView(scope: app.inbox.scope, status: app.syncStatus,
                                  hasSeenMail: app.inbox.hasSeenMail,
                                  onRetry: { Task { await app.syncMailNow() } })
                } else {
                    MessageListView(sections: app.sections,
                                    selectedIndex: app.inbox.selectedIndex,
                                    markedIndices: app.inbox.markedIndices,
                                    name: { app.inbox.correspondent(of: $0) },
                                    date: { app.inbox.rowDate(of: $0) },
                                    rowHeight: app.preferences.listRowHeight,
                                    previewLines: app.preferences.previewLines,
                                    labelNames: { thread in
                                        ThreadDetail.labels(on: thread.labelIDs, known: app.labels)
                                            .map(\.displayName)
                                    },
                                    onSelect: { app.inbox.select(index: $0) },
                                    onOpen: { app.perform(.openSelected) })
                }
                Divider()
                StatusBar(status: app.syncStatus, count: app.inbox.threads.count,
                          unread: app.visibleUnreadCount, isFocused: app.isFocused)
            }
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)

            Group {
                if let thread = app.inbox.selectedThread {
                    VStack(spacing: 0) {
                        AssistantPanel(model: app.assistant,
                                       onUseSuggestion: { app.startReply(with: $0) },
                                       onRunDraft: { app.runAssistantDraft() })
                        ThreadView(thread: thread,
                                   messages: app.inbox.selectedMessages,
                                   isExpanded: { app.inbox.isExpanded($0) },
                                   onToggle: { app.inbox.toggleExpansion($0) },
                                   attachments: { app.inbox.attachments(forMessage: $0) },
                                   attachmentModel: app.attachments,
                                   alwaysLoadsImages: app.alwaysLoadsImages,
                                   knownLabels: app.labels,
                                   onUnsubscribe: { app.unsubscribeSelected() })
                    }
                } else {
                    // Whatever there is to say about an empty inbox, the list
                    // says it; repeating it here would just be it twice.
                    Color.clear
                }
            }
            .frame(minWidth: 420, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        }
    }
}

/// What an empty inbox says for itself.
///
/// An empty table reads as a loading failure rather than as success, and
/// finishing is the thing this app is for.
/// Names the list you are looking at. Without it, Inbox and Sent are two
/// identical columns of names and dates.
struct MailboxHeader: View {
    let title: String
    let count: Int
    /// How much of the list has not been read. Shown as a badge rather than
    /// another grey number, because it is the one worth reacting to.
    var unread: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.tint, in: Capsule())
            }
            Text("\(count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unread > 0
                            ? "\(title), \(unread) unread of \(count)"
                            : "\(title), \(count) messages")
    }
}

struct EmptyListView: View {
    let scope: MailScope
    let status: SyncStatus
    /// Whether any mail has ever reached this session. Without it a fresh
    /// install and a finished morning of triage look identical.
    let hasSeenMail: Bool
    /// What to do when the reader takes the app up on its offer. Absent in
    /// demo mode, where there is no Gmail to reach.
    var onRetry: (() -> Void)?

    var body: some View {
        let state = EmptyState.of(scope: scope, status: status, hasSeenMail: hasSeenMail)
        VStack(spacing: 10) {
            // Motion rather than a verdict, and in the symbol's place rather
            // than above it.
            if state.isWaiting {
                ProgressView().controlSize(.small).frame(height: 34)
            } else {
                Image(systemName: state.symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            Text(state.headline).font(.title3.weight(.medium))
            Text(state.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if let retry = state.retry, let onRetry {
                Button(retry, action: onRetry)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.headline). \(state.detail)")
    }
}

/// The subtle "offline / syncing" indicator the v1 design asks for.
struct StatusBar: View {
    let status: SyncStatus
    let count: Int
    let unread: Int
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6).foregroundStyle(colour)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if isFocused {
                Image(systemName: "moon.fill").font(.caption2).foregroundStyle(.secondary)
            } else if unread > 0 {
                Text("\(unread) unread").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private var colour: Color {
        switch status {
        case .idle: return .secondary
        case .syncing: return .blue
        case .upToDate: return .green
        case .offline: return .orange
        case .failed: return .red
        }
    }

    private var label: String {
        switch status {
        case .idle: return "Not synced"
        case .syncing: return "Syncing…"
        case let .upToDate(at): return "Updated \(at.formatted(date: .omitted, time: .shortened))"
        case let .offline(failures): return "Offline (retry \(failures))"
        case let .failed(reason): return "Sync problem: \(reason)"
        }
    }
}
