import SwiftUI

/// Explains the gaps where a message's pictures would be.
///
/// Blocking them is the right default -- a remote image is how a sender learns
/// their message was opened, and by whom, and when -- but a reader looking at
/// an empty rectangle has been told nothing. This says what happened and what
/// it costs to undo, and asks rather than deciding.
struct RemoteImageBar: View {
    let onLoad: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
            Text("Images not loaded")
                .font(.caption)
            Text("Loading them tells the sender you opened this")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Load images", action: onLoad)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 24).padding(.vertical, 7)
        .background(.quaternary.opacity(0.3))
    }
}
