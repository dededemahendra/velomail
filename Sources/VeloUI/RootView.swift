import SwiftUI
import VeloCore


/// Routes to whichever surface the app state says is focused, and hosts the
/// single key monitor that drives the whole app.
public struct RootView: View {
    @ObservedObject var app: AppViewModel

    public init(app: AppViewModel) { self.app = app }

    public var body: some View {
        Group {
            switch app.route {
            case .setup:
                SetupView(clientIDHint: app.setupHint)
            case .signIn:
                SignInView(state: app.authState, onSignIn: app.signIn)
            case .search:
                SearchView(model: app.search,
                           isAIEnabled: app.assistant.isAvailable,
                           onOpen: { app.openFromSearch($0) },
                           onCancel: { app.perform(.back) })
            case .compose:
                ComposeView(model: app.compose,
                            assistant: app.assistant,
                            onSend: { app.perform(.send) },
                            onCancel: { app.perform(.back) })
            default:
                mailSurface
            }
        }
        .overlay(alignment: .bottom) {
            if app.undoableSend != nil {
                UndoBanner(onUndo: { app.undoLastSend() })
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.undoableSend)
        .overlay(alignment: .top) {
            if app.route == .palette {
                CommandPaletteView(registry: app.palette,
                                   onRun: { app.perform($0) },
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
                MessageListView(threads: app.inbox.threads,
                                selectedIndex: app.inbox.selectedIndex,
                                onSelect: { app.inbox.select(index: $0) },
                                onOpen: { app.perform(.openSelected) })
                Divider()
                StatusBar(status: app.syncStatus, count: app.inbox.threads.count)
            }
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)

            Group {
                if let thread = app.inbox.selectedThread {
                    VStack(spacing: 0) {
                        AssistantPanel(model: app.assistant,
                                       onUseSuggestion: { app.startReply(with: $0) })
                        ThreadView(thread: thread,
                               messages: app.inbox.selectedMessages,
                                   isExpanded: { app.inbox.isExpanded($0) },
                                   onToggle: { app.inbox.toggleExpansion($0) })
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("Inbox zero").font(.title3.weight(.medium))
                        Text("Nothing left to triage.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420)
        }
    }
}

/// The subtle "offline / syncing" indicator the v1 design asks for.
struct StatusBar: View {
    let status: SyncStatus
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6).foregroundStyle(colour)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
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
