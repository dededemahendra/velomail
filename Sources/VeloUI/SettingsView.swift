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
    var onClose: () -> Void = {}

    /// The sections, in the order someone would go looking for them: who you
    /// are, then how you write, then what the app does on its own.
    enum Section: String, CaseIterable, Identifiable {
        case accounts, writing, composing, snippets, reading, timing, rules, ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accounts: return "Accounts"
            case .writing: return "Writing"
            case .composing: return "Composing"
            case .snippets: return "Snippets"
            case .reading: return "Reading"
            case .timing: return "Timing"
            case .rules: return "Rules"
            case .ai: return "AI"
            }
        }

        var symbol: String {
            switch self {
            case .accounts: return "person.crop.circle"
            case .writing: return "signature"
            case .composing: return "arrowshape.turn.up.left"
            case .snippets: return "text.badge.plus"
            case .reading: return "eye"
            case .timing: return "timer"
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
            case .composing: return "What happens when you answer, and before a message goes."
            case .snippets: return "Short things you type often."
            case .reading: return "What the app shows you, and when it interrupts."
            case .timing: return "How long the app waits before doing what you asked."
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            Divider()
            // A window with no visible way out is a window people force-quit.
            // Escape closes it too, but only once you have guessed that.
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: 680, height: 500)
        .onAppear { if section == nil { section = startingSection } }
        // Saved on the way out rather than on every keystroke: a half-typed
        // shortcut should not be written and read back mid-edit.
        .onDisappear { model.save() }
        .onExitCommand(perform: onClose)
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
                    case .composing: composingTab
                    case .snippets: snippetsTab
                    case .reading: readingTab
                    case .timing: timingTab
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

    /// A key as it looks on the keyboard, so a sentence about one does not
    /// read as a stray character. "r answers everyone" looks like a typo.
    private func key(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
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

    // MARK: - Composing

    private var composingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Replying",
                  footnote: "Shift-R always answers everyone, whichever way this is set. "
                  + "Turning this on makes both keys do the same thing.") {
                Toggle(isOn: $model.repliesToEveryone) {
                    HStack(spacing: 6) {
                        Text("Pressing")
                        key("R")
                        Text("replies to everyone on the message")
                    }
                }
                .controlSize(.small)
                Divider().opacity(0.4)
                Toggle("Quote the message being answered", isOn: $model.quotesByDefault)
                    .controlSize(.small)
            }

            group("Before sending",
                  footnote: "Asked only for these two. A client that questions every send "
                  + "teaches people to dismiss it without reading.") {
                Toggle("Ask when a message mentions an attachment but has none",
                       isOn: $model.warnsAboutAttachments)
                    .controlSize(.small)
                Divider().opacity(0.4)
                Stepper(value: $model.recipientLimit, in: 0...100, step: 1) {
                    HStack {
                        Text("Ask above")
                        Spacer()
                        Text(model.recipientLimit == 0
                             ? "Never"
                             : "\(Int(model.recipientLimit)) recipients")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .controlSize(.small)
            }
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
                        .accessibilityLabel("Delete snippet \(snippet.name)")
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

    // MARK: - Reading

    private var readingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Images",
                  footnote: "A picture that lives on a server tells the sender you opened "
                  + "the message, when, and roughly where from. Pictures a message brings "
                  + "with it are always shown.") {
                Toggle("Load images in messages", isOn: $model.loadsImages)
                    .controlSize(.small)
            }

            group("Opening",
                  footnote: "Which list is on screen when the app starts.") {
                Picker("Opening list", selection: $model.opensAt) {
                    Text("Inbox").tag("inbox")
                    Text("Starred").tag("starred")
                    Text("Snoozed").tag("snoozed")
                    Text("Sent").tag("sent")
                }
                .pickerStyle(.radioGroup).labelsHidden().accessibilityElement(children: .contain)
            }

            group("Marking as read",
                  footnote: "Never is for triaging: open a thread to look at it without "
                  + "losing track of what you have not dealt with.") {
                Picker("Mark as read", selection: $model.marksReadAfter) {
                    Text("As soon as it opens").tag(0.0)
                    Text("After 2 seconds").tag(2.0)
                    Text("After 5 seconds").tag(5.0)
                    Text("Never").tag(-1.0)
                }
                .pickerStyle(.radioGroup).labelsHidden().accessibilityElement(children: .contain)
            }

            group("The list",
                  footnote: "Compact fits about half again as many messages on screen.") {
                Picker("List density", selection: $model.compactList) {
                    Text("Comfortable").tag(false)
                    Text("Compact").tag(true)
                }
                .pickerStyle(.radioGroup).labelsHidden().accessibilityElement(children: .contain)
                Divider().opacity(0.4)
                Stepper(value: $model.previewLines, in: 0...3, step: 1) {
                    HStack {
                        Text("Lines of the message")
                        Spacer()
                        Text(model.previewLines == 0
                             ? "None"
                             : "\(Int(model.previewLines))")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .controlSize(.small)
            }

            group("Threads",
                  footnote: "Oldest first is the order the conversation happened in.") {
                Picker("Thread order", selection: $model.newestFirstInThread) {
                    Text("Oldest message first").tag(false)
                    Text("Newest message first").tag(true)
                }
                .pickerStyle(.radioGroup).labelsHidden().accessibilityElement(children: .contain)
            }

            group("Notifications",
                  footnote: "Focus mode silences these for a while without changing the setting.") {
                Toggle("Announce new mail and badge the Dock", isOn: $model.showsNotifications)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Timing

    private var timingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Undo",
                  footnote: "Long enough to catch a mistake, short enough that the reply "
                  + "does not look late.") {
                Stepper(value: $model.undoWindow, in: 3...60, step: 1) {
                    HStack {
                        Text("A sent message waits")
                        Spacer()
                        Text("\(Int(model.undoWindow)) seconds")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .controlSize(.small)
            }

            group("Snooze",
                  footnote: "Tomorrow and next week both wake at the hour set here.") {
                Stepper(value: $model.snoozeHours, in: 1...72, step: 1) {
                    HStack(spacing: 6) {
                        Text("Pressing")
                        key("H")
                        Text("puts a thread off for")
                        Spacer()
                        Text("\(Int(model.snoozeHours)) hours")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .controlSize(.small)
                Divider().opacity(0.4)
                Stepper(value: $model.morningHour, in: 0...23, step: 1) {
                    HStack {
                        Text("Morning starts at")
                        Spacer()
                        Text(String(format: "%02d:00", model.morningHour))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .controlSize(.small)
            }

            group("Checking for mail",
                  footnote: "Takes effect next time the app starts.") {
                Stepper(value: $model.syncMinutes, in: 0.25...60, step: 0.25) {
                    HStack {
                        Text("Check every")
                        Spacer()
                        Text(model.syncMinutes < 1
                             ? "\(Int(model.syncMinutes * 60)) seconds"
                             : "\(model.syncMinutes.formatted()) min")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Rules

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($model.rules) { $rule in
                group {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.isEnabled)
                            .labelsHidden().controlSize(.small)
                            .accessibilityLabel(rule.isEnabled
                                                ? "Rule on, \(rule.name)"
                                                : "Rule off, \(rule.name)")
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
                        .accessibilityLabel("Delete rule \(rule.name)")
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
                    if rule.hasMoreToIt {
                        // Otherwise these two fields read as the whole rule,
                        // and turning Archive off looks like turning the rule
                        // off when it still does something else entirely.
                        Label("Also \(rule.extraSummary). Edit rules.json to change that.",
                              systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.top, 2)
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
                .accessibilityLabel("AI provider")
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
