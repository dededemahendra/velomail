import SwiftUI
import VeloCore

/// Full-window search: a field, ranked results, Enter to open.
struct SearchView: View {
    @ObservedObject var model: SearchViewModel
    let isAIEnabled: Bool
    let onOpen: (MailThread) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            results
        }
        .onAppear { isFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $model.text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFocused)
                .onSubmit { Task { await model.run() } }
            if model.isSearching { ProgressView().controlSize(.small) }
            Button("Close", action: onCancel).buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// The placeholder is the only hint that plain English works, so it changes
    /// with whether a model is actually configured rather than promising
    /// something the app cannot do.
    private var placeholder: String {
        isAIEnabled
            ? "Search, or describe it — \"unread from natalie last week\""
            : "Search mail"
    }

    @ViewBuilder
    private var results: some View {
        if let failure = model.failure {
            message(failure)
        } else if model.results.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, thread in
                        row(thread, isSelected: index == model.selectedIndex)
                            .onTapGesture { onOpen(thread) }
                    }
                }
            }
        }
    }

    private func row(_ thread: MailThread, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(MailFormatting.displayName(thread.sender))
                    .font(.callout.weight(thread.isUnread ? .semibold : .regular))
                Spacer()
                Text(MailFormatting.relativeDate(thread.lastMessageDate))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(thread.snippet)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }

    /// Says what can be typed rather than only that something can be.
    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: model.text.isEmpty ? "magnifyingglass" : "tray")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(model.text.isEmpty ? "Search your mail" : "No matching mail")
                .font(.system(size: 13, weight: .medium))
            Text(model.text.isEmpty
                 ? (isAIEnabled
                    ? "Keywords, or plain English like “unread from natalie last week”."
                    : "Searches senders, subjects and message text.")
                 : "Try fewer words, or a different sender.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
