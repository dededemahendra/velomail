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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
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
