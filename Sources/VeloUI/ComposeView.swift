import SwiftUI

struct ComposeView: View {
    @ObservedObject var model: ComposeViewModel
    let onSend: () -> Void
    let onCancel: () -> Void

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
                TextEditor(text: $model.body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
