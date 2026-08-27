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

    var body: some View {
        TabView {
            accountsTab.tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            writingTab.tabItem { Label("Writing", systemImage: "square.and.pencil") }
            snippetsTab.tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            rulesTab.tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease.circle") }
            aiTab.tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 560, height: 420)
        .onDisappear { model.save() }
    }

    // MARK: - Accounts

    private var accountsTab: some View {
        Form {
            Section {
                ForEach(accounts) { account in
                    HStack {
                        Image(systemName: account.id == currentAccount
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(account.id == currentAccount
                                             ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        Text(account.displayName)
                        Spacer()
                        if account.id != currentAccount {
                            Button("Open") { onSwitchAccount(account.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Mailboxes")
            } footer: {
                // Said here because it is the one thing about accounts that is
                // not obvious and cannot be undone by switching back.
                Text("Each mailbox keeps its own database and sign-in. Nothing is shared between them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Add another account", action: onAddAccount)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Writing

    private var writingTab: some View {
        Form {
            Section {
                TextEditor(text: $model.signature)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 140)
            } header: {
                Text("Signature")
            } footer: {
                Text("Added below what you write, above the quoted message.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            status
        }
        .formStyle(.grouped)
    }

    // MARK: - Snippets

    private var snippetsTab: some View {
        Form {
            Section {
                ForEach($model.snippets) { $snippet in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $snippet.name)
                            Text(";").foregroundStyle(.tertiary)
                            TextField("shortcut", text: $snippet.shortcut)
                                .frame(width: 110)
                            Button {
                                model.snippets.removeAll { $0.id == snippet.id }
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        TextField("What it types", text: $snippet.body, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    .padding(.vertical, 2)
                }
                Button("Add snippet") { model.addSnippet() }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Type the shortcut with a leading semicolon while writing to expand it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            status
        }
        .formStyle(.grouped)
    }

    // MARK: - Rules

    private var rulesTab: some View {
        Form {
            Section {
                ForEach($model.rules) { $rule in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("", isOn: $rule.isEnabled).labelsHidden()
                            TextField("Name", text: $rule.name)
                            Button {
                                model.rules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("From contains").font(.caption).foregroundStyle(.secondary)
                            TextField("example.com", text: $rule.senderContains)
                        }
                        Toggle("Archive it", isOn: $rule.archives)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                Button("Add rule") { model.addRule() }
            } header: {
                Text("Rules")
            } footer: {
                // Rules act without asking. Saying so is the least a window
                // that creates them can do.
                Text("Rules run on new mail as it arrives, without asking. "
                     + "Turn one off rather than deleting it if you are unsure.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            status
        }
        .formStyle(.grouped)
    }

    // MARK: - AI

    private var aiTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $model.aiProvider) {
                    Text("Off").tag("")
                    Text("Anthropic").tag("anthropic")
                    Text("Ollama (on this Mac)").tag("ollama")
                }
                TextField("Model", text: $model.aiModel)
                if model.aiProvider == "anthropic" {
                    SecureField("API key", text: $model.aiAPIKey)
                }
            } header: {
                Text("Writing assistance")
            } footer: {
                Text(model.aiProvider == "ollama"
                     ? "Nothing leaves this Mac."
                     : "Message text is sent to the provider when you use an AI command.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            status
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var status: some View {
        if case let .failed(message) = model.status {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
