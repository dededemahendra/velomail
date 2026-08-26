import SwiftUI
import VeloCore

/// The Cmd+K palette. Filtering and ranking come from `CommandRegistry`; this
/// only renders them.
struct CommandPaletteView: View {
    let registry: CommandRegistry
    let onRun: (MailAction) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private var results: [Command] { registry.matches(query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(16)
                .focused($isFocused)
                .onSubmit(runHighlighted)
                .onChange(of: query) { _, _ in highlighted = 0 }
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, command in
                        HStack(spacing: 10) {
                            Text(command.title)
                            Spacer(minLength: 12)
                            // The hint is what turns the palette from a menu
                            // into the thing that teaches the keymap.
                            if let shortcut = KeyboardEngine.shortcutLabel(for: command.action) {
                                Text(shortcut)
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(index == highlighted ? .secondary : .tertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary.opacity(0.6),
                                                in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(index == highlighted ? Color.accentColor.opacity(0.18) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { onRun(command.action) }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { isFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private func runHighlighted() {
        guard results.indices.contains(highlighted) else { return }
        onRun(results[highlighted].action)
    }
}
