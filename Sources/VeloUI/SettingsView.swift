import SwiftUI
import VeloCore

/// Everything the app reads from a file, in a window instead.
///
/// It writes the same files, so nothing here is a second source of truth and
/// the rules stay readable in a text editor -- which is the whole reason they
/// are a file.
struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    let accounts: [Account]
    let currentAccount: String
    let onSwitchAccount: (String) -> Void
    let onAddAccount: () -> Void

    /// The sections, in the order someone would go looking for them: who you
    /// are, then how you write, then what the app does on its own.
    enum Section: String, CaseIterable, Identifiable {
        case accounts, writing, snippets, rules, ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accounts: return "Accounts"
            case .writing: return "Writing"
            case .snippets: return "Snippets"
            case .rules: return "Rules"
            case .ai: return "AI"
            }
        }

        var symbol: String {
            switch self {
            case .accounts: return "person.crop.circle"
            case .writing: return "signature"
            case .snippets: return "text.badge.plus"
            case .rules: return "line.3.horizontal.decrease.circle"
            case .ai: return "sparkles"
            }
        }

        /// One line under the title saying what the section is for, so a person
        /// can tell whether they are in the right place without reading it all.
        var summary: String {
            switch self {
            case .accounts: return "The mailboxes this app knows about."
            case .writing: return "What goes at the bottom of everything you send."
            case .snippets: return "Short things you type often."
            case .rules: return "What happens to mail before you see it."
            case .ai: return "Optional, and off unless you turn it on."
            }
        }
    }

    /// Which pane opens first. Settable so a snapshot can look at one that is
    /// not the default.
    var startingSection: Section = .accounts
    @State private var section: Section?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: 460)
        .onAppear { if section == nil { section = startingSection } }
        .onDisappear { model.save() }
    }

    /// The pane on show, before `onAppear` has run in a snapshot.
    private var current: Section { section ?? startingSection }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12))
                            .frame(width: 18)
                            .foregroundStyle(current == item
                                             ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(item.title).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background {
                        if current == item {
                            RoundedRectangle(cornerRadius: 7).fill(.tint.opacity(0.16))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 180, alignment: .top)
        .background(.quaternary.opacity(0.18))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(current.title).font(.system(size: 15, weight: .semibold))
                Text(current.summary).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch current {
                    case .accounts: accountsTab
                    case .writing: writingTab
                    case .snippets: snippetsTab
                    case .rules: rulesTab
                    case .ai: aiTab
                    }
                    status
                }
                .padding(.horizontal, 22).padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A titled group of controls, so a pane reads as sections rather than a
    /// column of unrelated rows.
    @ViewBuilder
    private func group<Content: View>(_ title: String? = nil, footnote: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Accounts

    private var accountsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(footnote: "Each mailbox keeps its own database and sign-in. "
                  + "Nothing is shared between them.") {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider().opacity(0.4) }
                    HStack(spacing: 10) {
                        Image(systemName: account.id == currentAccount
                              ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(account.id == currentAccount
                                             ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.displayName).font(.system(size: 13))
                            if account.id == currentAccount {
                                Text("Open").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if account.id != currentAccount {
                            Button("Open") { onSwitchAccount(account.id) }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                }
            }

            Button {
                onAddAccount()
            } label: {
                Label("Add another account", systemImage: "plus")
            }
        }
    }

    // MARK: - Writing

    private var writingTab: some View {
        group("Signature", footnote: "Added below what you write, above the quoted message.") {
            TextEditor(text: $model.signature)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
        }
    }

    // MARK: - Snippets

    private var snippetsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($model.snippets) { $snippet in
                group {
                    HStack(spacing: 8) {
                        TextField("Name", text: $snippet.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(";").foregroundStyle(.tertiary).font(.system(size: 12))
                        TextField("shortcut", text: $snippet.shortcut)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 90)
                        Button {
                            model.snippets.removeAll { $0.id == snippet.id }
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.4)
                    TextField("What it types", text: $snippet.body, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(2...6)
                }
            }

            Button { model.addSnippet() } label: {
                Label("Add snippet", systemImage: "plus")
            }

            Text("Type the shortcut with a leading semicolon while writing to expand it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Rules

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($model.rules) { $rule in
                group {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.isEnabled).labelsHidden().controlSize(.small)
                        TextField("Name", text: $rule.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            model.rules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.4)
                    HStack(spacing: 8) {
                        Text("From contains")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        TextField("example.com", text: $rule.senderContains)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    HStack(spacing: 8) {
                        Text("Then")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        Toggle("Archive it", isOn: $rule.archives).controlSize(.small)
                    }
                }
                .opacity(rule.isEnabled ? 1 : 0.55)
            }

            Button { model.addRule() } label: {
                Label("Add rule", systemImage: "plus")
            }

            // Rules act without asking. Saying so is the least a window that
            // creates them can do.
            Label("Rules run on new mail as it arrives, without asking. "
                  + "Turn one off rather than deleting it if you are unsure.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Writing assistance") {
                Picker("Provider", selection: $model.aiProvider) {
                    Text("Off").tag("")
                    Text("Anthropic").tag("anthropic")
                    Text("Ollama, on this Mac").tag("ollama")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if !model.aiProvider.isEmpty {
                group("Model") {
                    TextField(model.aiProvider == "ollama" ? "llama3" : "claude-opus-5",
                              text: $model.aiModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                    if model.aiProvider == "anthropic" {
                        Divider().opacity(0.4)
                        SecureField("API key", text: $model.aiAPIKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            Label(model.aiProvider == "ollama"
                  ? "Nothing leaves this Mac."
                  : model.aiProvider.isEmpty
                    ? "No AI commands appear until a provider is chosen."
                    : "Message text is sent to Anthropic when you use an AI command.",
                  systemImage: model.aiProvider == "ollama" ? "lock" : "info.circle")
                .font(.caption).foregroundStyle(.secondary)

            Text("Changing the provider takes effect next time the app starts.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var status: some View {
        if case let .failed(message) = model.status {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
