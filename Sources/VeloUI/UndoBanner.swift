import SwiftUI
import VeloCore

/// The undo-send strip. Present only while the window is open, which is what
/// makes the promise honest: once it goes, the mail is gone.
struct UndoBanner: View {
    let prompt: String
    var symbol: String = "arrow.uturn.backward"
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.caption)
                .accessibilityHidden(true)
            Text(prompt).font(.callout)
            Spacer()
            // The shortcut is the way this is meant to be used; the button is
            // for the times the writer has already reached for the mouse.
            Text("\u{2318}Z").font(.caption2).foregroundStyle(.tertiary)
            Button("Undo", action: onUndo)
                .buttonStyle(.borderless)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// What the queue gave up on.
///
/// Deliberately unlike `UndoBanner`: no countdown and no automatic dismissal.
/// A message that never went is not a ten second offer, and the writer has to
/// be the one who decides it has been dealt with.
struct FailureBanner: View {
    let prompt: String
    /// Present only when there is a draft to put back in the composer.
    let canReopen: Bool
    /// How many more are waiting behind this one.
    var overflow: Int = 0
    let onReopen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(prompt).font(.callout).lineLimit(1)
            if overflow > 0 {
                Text("+\(overflow) more").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if canReopen {
                Button("Reopen", action: onReopen).buttonStyle(.borderless)
            }
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt)
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A plain answer to something the writer just asked for.
///
/// No action and no countdown of its own: it says what happened and gets out
/// of the way when the next thing does.
struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(.callout)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Threads you are waiting on, shown by `g f`.
struct FollowUpBar: View {
    let threads: [MailThread]
    let onDismiss: () -> Void
    let onOpen: (MailThread) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").font(.caption)
                Text("AWAITING REPLY").font(.caption.weight(.semibold))
                Spacer()
                Button { onDismiss() } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            if threads.isEmpty {
                Text("Nothing is waiting on a reply.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(threads) { thread in
                    Button { onOpen(thread) } label: {
                        HStack {
                            Text(thread.snippet).font(.callout).lineLimit(1)
                            Spacer()
                            Text(MailFormatting.relativeDate(thread.lastMessageDate))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.quaternary.opacity(0.35))
    }
}
