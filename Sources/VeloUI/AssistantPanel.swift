import SwiftUI
import VeloCore

/// The AI result surface: a strip above the thread that appears when an
/// operation runs and can be dismissed.
///
/// It sits above the message rather than replacing it, because a summary is
/// something you read *alongside* the thread, not instead of it.
struct AssistantPanel: View {
    @ObservedObject var model: AssistantViewModel
    let onUseSuggestion: (String) -> Void

    var body: some View {
        if model.state != .idle {
            VStack(alignment: .leading, spacing: 10) {
                header
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.35))
            Divider()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let name = model.providerName {
                // Say which model answered; a local and a hosted answer are not
                // interchangeable and the user should know which they got.
                Text(name).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                model.dismiss()
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Thinking…").font(.callout).foregroundStyle(.secondary)
            }
        case let .result(text):
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case let .suggestions(replies):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(replies.enumerated()), id: \.offset) { _, reply in
                    Button {
                        onUseSuggestion(reply)
                    } label: {
                        HStack {
                            Text(reply).font(.callout).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.turn.down.left")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case let .failed(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch model.state {
        case .suggestions: return "SUGGESTED REPLIES"
        case .failed: return "ASSISTANT"
        default: return "SUMMARY"
        }
    }
}
