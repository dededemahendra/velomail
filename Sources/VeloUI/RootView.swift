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
                MailboxHeader(title: app.inbox.title, count: app.inbox.threads.count)
                Divider()
                if app.inbox.threads.isEmpty {
                    EmptyListView(scope: app.inbox.scope)
                } else {
                    MessageListView(sections: app.sections,
                                    selectedIndex: app.inbox.selectedIndex,
                                    markedIndices: app.inbox.markedIndices,
                                    name: { app.inbox.correspondent(of: $0) },
                                    date: { app.inbox.rowDate(of: $0) },
                                    rowHeight: app.preferences.listRowHeight,
                                    previewLines: app.preferences.previewLines,
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

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

struct EmptyListView: View {
    let scope: MailScope

    var symbol: String {
        switch scope {
        case .inbox: return "checkmark.circle"
        case .sent: return "paperplane"
        case .snoozed: return "clock"
        case .starred: return "star"
        case .archive: return "archivebox"
        case .label: return "tag"
        }
    }

    var headline: String {
        switch scope {
        case .inbox: return "Inbox zero"
        case .sent: return "Nothing sent yet"
        case .snoozed: return "Nothing snoozed"
        case .starred: return "Nothing starred"
        case .archive: return "Nothing filed away"
        case let .label(_, name): return "Nothing in \(name)"
        }
    }

    var detail: String {
        switch scope {
        case .inbox: return "Nothing left to triage."
        case .sent: return "Messages you send appear here."
        case .snoozed: return "Threads you put off come back here."
        case .starred: return "Press s on a thread to keep it to hand."
        case .archive: return "Threads you archive with e wait here."
        case .label: return "File a thread here from the command palette."
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(headline).font(.title3.weight(.medium))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
