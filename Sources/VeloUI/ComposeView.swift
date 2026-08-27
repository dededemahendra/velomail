import SwiftUI
import AppKit
import VeloCore

struct ComposeView: View {
    @ObservedObject var model: ComposeViewModel
    @ObservedObject var assistant: AssistantViewModel
    let onSend: () -> Void
    var onSendLater: (Date) -> Void = { _ in }
    let onCancel: () -> Void

    @State private var isWorking = false
    @State private var attachmentError: String?
    /// Bcc is revealed rather than always shown. A standing blind-copy field is
    /// how one gets filled in by accident.
    @State private var isShowingBcc = false
    /// True while a file is over the window, so there is something to aim at.
    @State private var isDropTarget = false
    /// The quote is collapsed by default. It is there to be sent, not read --
    /// the writer just saw the message they are answering.
    @State private var isShowingQuote = false
    /// Capped at open so a long parent does not push the editor off screen.
    @State private var quoteHeight: CGFloat = 160
    /// Set by a toolbar press, consumed by the editor that owns the selection.
    @State private var pendingStyle: MarkdownFormatting.Style?

    /// The composer's left edge. Every row uses it, so the labels, the toolbar
    /// and the first character of the message all start in the same place --
    /// three rows with three ideas of the margin is what "not balanced" looks
    /// like even when no single row is wrong.
    static let gutter: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(model.headline)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Menu("Later") {
                    Button("Tomorrow morning") { onSendLater(Horizon.tomorrow()) }
                    Button("Next week") { onSendLater(Horizon.nextWeek()) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!model.canSend)
                .help("Write it now, let it arrive at a better hour")
                Button("Send", action: onSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSend)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            VStack(spacing: 0) {
                field("To", placeholder: "name@example.com", text: $model.to,
                      onKey: handleRecipientKey)
                if !model.suggestions.isEmpty { suggestionList }
                Divider()
                // Always present rather than revealed by a control: a hidden Cc
                // is one people forget exists, and reply-all fills it.
                field("Cc", placeholder: "Optional", text: $model.cc) { bccToggle }
                Divider()
                if isShowingBcc || !model.bcc.isEmpty {
                    field("Bcc", placeholder: "Hidden from the others", text: $model.bcc)
                    Divider()
                }
                field("Subject", placeholder: "Subject", text: $model.subject)
                Divider()
                attachmentBar
                if assistant.isAvailable { assistantBar }
                if let quoted = model.quotedSummary { quoteStrip(quoted) }
                formattingBar
                Divider()
                ZStack(alignment: .topLeading) {
                    if model.body.isEmpty {
                        Text("Write your message…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            // The editor's own numbers, so the placeholder sits
                            // exactly where the first character will.
                            .padding(.leading, MarkdownEditor.textOrigin.width)
                            .padding(.top, MarkdownEditor.textOrigin.height)
                            .allowsHitTesting(false)
                    }
                    MarkdownEditor(text: $model.body, pending: $pendingStyle)
                        .onChange(of: model.body) { _, _ in model.autosave() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dropping a file on a message is the most reflexive thing anybody
        // does with an attachment, and it did nothing at all.
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            receive(providers)
            return true
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Loads what was dropped and attaches it, naming anything that would not
    /// come. A drop that silently attaches four of five files is worse than one
    /// that says which was refused.
    private func receive(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                guard let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url")
                        as? Data,
                      let resolved = URL(dataRepresentation: url, relativeTo: nil) else { continue }
                urls.append(resolved)
            }
            let failed = model.attach(urls)
            attachmentError = failed.isEmpty
                ? nil
                : "Could not attach \(failed.joined(separator: ", "))."
        }
    }

    /// The marks `MarkdownBody` understands, as buttons.
    ///
    /// They type the same characters a writer would; nothing here is a
    /// different kind of formatting from what you can write by hand, which is
    /// what keeps one representation for the body rather than two.
    private var formattingBar: some View {
        HStack(spacing: 2) {
            styleButton(.bold, "bold", "Bold", "b")
            styleButton(.italic, "italic", "Italic", "i")
            styleButton(.code, "chevron.left.forwardslash.chevron.right", "Code", nil)
            styleButton(.link, "link", "Link", "k")
            Divider().frame(height: 14).padding(.horizontal, 5)
            styleButton(.bullet, "list.bullet", "Bulleted list", nil)
            styleButton(.numbered, "list.number", "Numbered list", nil)
            styleButton(.quote, "text.quote", "Quote", nil)
            Spacer()
            if model.isRichText {
                Label("Formatted", systemImage: "textformat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("This message will be sent as formatted text as well as plain")
            }
        }
        .padding(.leading, ComposeView.gutter - 6).padding(.trailing, ComposeView.gutter)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func styleButton(_ style: MarkdownFormatting.Style, _ symbol: String,
                             _ name: String, _ key: Character?) -> some View {
        let button = Button {
            pendingStyle = style
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(key.map { "\(name) (\u{2318}\(String($0).uppercased()))" } ?? name)
        .accessibilityLabel(name)

        if let key {
            button.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            button
        }
    }

    /// What is being answered, in one line, with the option to read it or drop
    /// it. Pasting it into the editor instead meant scrolling past a wall of
    /// someone else's text to reach your own.
    @ViewBuilder private func quoteStrip(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isShowingQuote.toggle()
                } label: {
                    Image(systemName: isShowingQuote ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isShowingQuote ? "Hide quoted message" : "Show quoted message")

                Image(systemName: "quote.opening").font(.caption2).foregroundStyle(.tertiary)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(model.includesQuote ? .secondary : .tertiary)
                    .strikethrough(!model.includesQuote)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Toggle("Include", isOn: $model.includesQuote)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel("Include the quoted message")
                    .help("Send the message you are answering underneath this one")
            }
            .padding(.horizontal, 20).padding(.vertical, 7)

            if isShowingQuote, let quoted = model.quotedMessage {
                // The same view the thread pane uses, so the quote looks like
                // the mail it came from. Capped: this is a glance to confirm
                // what is being answered, not somewhere to read a newsletter.
                // Inset and rounded: the quote is a card of somebody else's
                // mail sitting inside this one, and a full-bleed white slab
                // running to the window edge reads as the composer breaking
                // rather than as a quotation.
                MessageBodyView.previewOfQuote(quoted,
                                               attachments: model.quotedAttachments,
                                               onMeasure: { quoteHeight = min($0, 220) })
                    .frame(height: quoteHeight)
                    .background(quoted.bodyHTML != nil
                                ? Color.white : Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary, lineWidth: 1))
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .background(.quaternary.opacity(0.22))
        Divider()
    }

    /// Reveals the Bcc row. Hidden again only when it is empty, so a filled
    /// blind copy can never be out of sight while the message is still open.
    @ViewBuilder private var bccToggle: some View {
        if !isShowingBcc && model.bcc.isEmpty {
            Button("Bcc") { isShowingBcc = true }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    /// People already written to, offered as the address is typed.
    ///
    /// The list sits under the field rather than floating over it: a popover
    /// here would cover the Cc row the writer is about to reach for.
    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.address) { index, contact in
                Button {
                    model.accept(contact)
                } label: {
                    HStack(spacing: 8) {
                        Text(contact.name ?? contact.address)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if contact.name != nil {
                            Text(contact.address)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(index == model.highlighted ? Color.accentColor.opacity(0.16) : .clear)
            }
        }
        .padding(.bottom, 4)
        .background(.quaternary.opacity(0.25))
    }

    /// Arrow keys and Return belong to the suggestion list while it is showing,
    /// and to the composer the rest of the time.
    private func handleRecipientKey(_ press: KeyPress) -> KeyPress.Result {
        guard !model.suggestions.isEmpty else { return .ignored }
        switch press.key {
        case .downArrow: model.moveHighlight(by: 1); return .handled
        case .upArrow: model.moveHighlight(by: -1); return .handled
        case .return, .tab: return model.acceptHighlighted() ? .handled : .ignored
        case .escape: model.dismissSuggestions(); return .handled
        default: return .ignored
        }
    }

    /// Files on the outgoing message, with a chip each.
    private var attachmentBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    attachFiles()
                } label: {
                    Label("Attach", systemImage: "paperclip").font(.caption)
                }
                .buttonStyle(.borderless)

                if !model.attachments.isEmpty {
                    Text(AttachmentViewModel.formattedSize(model.attachmentBytes))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let attachmentError {
                    Text(attachmentError).font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }

            if !model.attachments.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(Array(model.attachments.enumerated()), id: \.offset) { index, file in
                        HStack(spacing: 6) {
                            Image(systemName: AttachmentViewModel.symbol(for: file.mimeType))
                                .font(.caption2)
                            Text(file.filename).font(.caption).lineLimit(1)
                            Button {
                                model.removeAttachment(at: index)
                                attachmentError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(file.filename)")
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    /// Opens the panel and attaches what was chosen, reporting the first
    /// refusal rather than silently dropping files.
    private func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        attachmentError = nil
        for url in panel.urls {
            do {
                try model.attach(url)
            } catch ComposeError.attachmentsTooLarge {
                attachmentError = "\(url.lastPathComponent) would take the message over the limit."
                break
            } catch {
                attachmentError = "Could not read \(url.lastPathComponent)."
                break
            }
        }
    }

    /// Writing assistance over whatever is currently in the editor. Each action
    /// replaces the body, so a failure must leave it untouched rather than
    /// wiping what the user wrote.
    private var assistantBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary)

            Menu("Tone") {
                ForEach(WritingTone.allCases, id: \.self) { tone in
                    Button(tone.rawValue.capitalized) {
                        apply { await assistant.rewrite(model.body, tone: tone) }
                    }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()

            Button("Fix grammar") { apply { await assistant.fixGrammar(model.body) } }
            Button("Shorten") { apply { await assistant.rewrite(model.body, tone: .direct) } }

            Menu("Translate") {
                ForEach(ComposeView.languages, id: \.self) { language in
                    Button(language) {
                        apply { await assistant.translate(model.body, to: language) }
                    }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()

            Button("Subject") {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    if let subject = await assistant.subjectLine(body: model.body) {
                        model.subject = subject
                    }
                }
            }
            .disabled(model.body.isEmpty)

            if isWorking { ProgressView().controlSize(.small) }
            Spacer()
            if case let .failed(message) = assistant.state {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 20).padding(.vertical, 7)
        .disabled(model.body.isEmpty || isWorking)
    }

    static let languages = ["Indonesian", "English", "Spanish", "French",
                            "German", "Japanese", "Mandarin Chinese"]

    /// Runs a transform and keeps the body only if it produced something.
    private func apply(_ operation: @escaping () async -> String?) {
        Task {
            isWorking = true
            defer { isWorking = false }
            if let text = await operation() { model.body = text }
        }
    }

    /// A labelled row that actually looks editable.
    ///
    /// A bare `.plain` field with no placeholder renders as nothing at all --
    /// the label alone reads as grey placeholder text, and there is no sign of
    /// where to type.
    private func field<Trailing: View>(
        _ label: String, placeholder: String, text: Binding<String>,
        onKey: @escaping (KeyPress) -> KeyPress.Result = { _ in .ignored },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onKeyPress(phases: .down, action: onKey)
                .onChange(of: text.wrappedValue) { _, _ in model.autosave() }
            trailing()
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
    }
}
