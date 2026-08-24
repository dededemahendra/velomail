import SwiftUI
import VeloCore

struct ComposeView: View {
    @ObservedObject var model: ComposeViewModel
    @ObservedObject var assistant: AssistantViewModel
    let onSend: () -> Void
    let onCancel: () -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.isReply ? "Reply" : "New message")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Send", action: onSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canSend)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            VStack(spacing: 0) {
                field("To", text: $model.to)
                Divider()
                field("Subject", text: $model.subject)
                Divider()
                if assistant.isAvailable { assistantBar }
                TextEditor(text: $model.body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            TextField("", text: text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
