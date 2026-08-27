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
        // The operators work either way, so they are the hint that is always
        // true. Plain English is offered only when something can read it.
        isAIEnabled
            ? "Search, from:someone, is:unread, or just describe it"
            : "Search, or from:someone, is:unread, after:week"
    }

    @ViewBuilder
    private var results: some View {
        if let failure = model.failure {
            message(failure)
        } else if model.results.isEmpty {
            emptyState
        } else {
            if !model.filterLabels.isEmpty {
                // Says what was narrowed. Without it there is no telling
                // whether from:cloudflare filtered or searched for the literal
                // string -- and with no results the two look identical.
                HStack(spacing: 6) {
                    ForEach(model.filterLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.tint.opacity(0.16),
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
            }

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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(MailFormatting.displayName(thread.sender))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if thread.hasAttachments {
                        Image(systemName: "paperclip").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if thread.isUnread {
                        Text("Unread")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }
                // The matched words, marked. Without them a result looks
                // arbitrary: searching "youtube" returns marketing mail whose
                // subject never says it, and nothing on the row explains why.
                highlighted(HTMLText.decoded(thread.snippet))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(MailFormatting.relativeDate(thread.lastMessageDate))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(isSelected
                    ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MailFormatting.rowDescription(
            thread, name: MailFormatting.displayName(thread.sender),
            date: MailFormatting.relativeDate(thread.lastMessageDate)))
    }

    /// The searched words picked out of the line they were found in.
    private func highlighted(_ text: String) -> Text {
        let words = model.text
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 2 && !$0.contains(":") }
        guard !words.isEmpty else { return Text(text) }

        var result = Text("")
        var remainder = Substring(text)
        while let match = words.compactMap({ word in
            remainder.range(of: word, options: .caseInsensitive)
        }).min(by: { $0.lowerBound < $1.lowerBound }) {
            result = result + Text(remainder[remainder.startIndex..<match.lowerBound])
            result = result + Text(remainder[match]).foregroundColor(.primary)
                .font(.system(size: 12, weight: .semibold))
            remainder = remainder[match.upperBound...]
        }
        return result + Text(remainder)
    }

    /// Says what can be typed rather than only that something can be.
    /// What fills the pane when there is nothing to list.
    ///
    /// Three different situations, not one: nothing typed and nothing to go on,
    /// nothing typed but a history to offer, and a query that found nothing.
    @ViewBuilder private var emptyState: some View {
        if model.text.isEmpty, !model.recents.isEmpty {
            recentSearches
        } else {
            VStack(spacing: 7) {
                Image(systemName: model.text.isEmpty ? "magnifyingglass" : "tray")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text(model.text.isEmpty ? "Search your mail" : "No matching mail")
                    .font(.system(size: 13, weight: .medium))
                Text(model.text.isEmpty
                     ? (isAIEnabled
                        ? "Keywords, or plain English like \u{201C}unread from natalie last week\u{201D}."
                        : "Searches senders, subjects and message text.")
                     : "Try fewer words, or a different sender.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 380, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    /// The last few searches, ready to run again.
    ///
    /// Typing the same query from memory is the commonest thing anyone does in
    /// a search field, and this app was asking for it every time.
    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("RECENT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 12).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.recents, id: \.self) { query in
                Button {
                    Task { await model.rerun(query) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(query).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
