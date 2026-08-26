import SwiftUI
import AppKit
import VeloCore

struct ComposeView: View {
    @ObservedObject var model: ComposeViewModel
    @ObservedObject var assistant: AssistantViewModel
    let onSend: () -> Void
    let onCancel: () -> Void

    @State private var isWorking = false
    @State private var attachmentError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(model.isReply ? "Reply" : "New message")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Send", action: onSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSend)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            VStack(spacing: 0) {
                field("To", placeholder: "name@example.com", text: $model.to)
                Divider()
                field("Subject", placeholder: "Subject", text: $model.subject)
                Divider()
                attachmentBar
                if assistant.isAvailable { assistantBar }
                ZStack(alignment: .topLeading) {
                    if model.body.isEmpty {
                        Text("Write your message…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 21).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.body)
                        .onChange(of: model.body) { _, _ in model.autosave() }
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private func field(_ label: String, placeholder: String,
                       text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: text.wrappedValue) { _, _ in model.autosave() }
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
    }
}
