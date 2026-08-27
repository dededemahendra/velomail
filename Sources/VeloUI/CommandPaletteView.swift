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
            field
            if !results.isEmpty {
                Divider().opacity(0.5)
                list
            } else if !query.isEmpty {
                empty
            }
        }
        .frame(width: 480)
        .floatingSurface(cornerRadius: 16, shadow: 30)
        .onAppear { isFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isFocused)
                .onSubmit(runHighlighted)
                .onChange(of: query) { _, _ in highlighted = 0 }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, command in
                    row(command, isHighlighted: index == highlighted)
                        .contentShape(Rectangle())
                        .onTapGesture { onRun(command.action) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        // The list is driven from the keyboard; a scroller is one more thing
        // drawn over the glass for no one.
        .scrollIndicators(.hidden)
        .frame(maxHeight: 320)
    }

    private func row(_ command: Command, isHighlighted: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: CommandSymbol.name(for: command.action))
                .font(.system(size: 13))
                .frame(width: 20, alignment: .center)
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text(command.title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            // The hint is what turns the palette from a menu into the thing
            // that teaches the keymap.
            if let shortcut = KeyboardEngine.shortcutLabel(for: command.action) {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary.opacity(isHighlighted ? 0.8 : 0.5),
                                in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        // Inset and rounded rather than a full-bleed bar: the selection should
        // sit on the surface, not cut across it.
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8).fill(.tint.opacity(0.22))
            }
        }
    }

    private var empty: some View {
        HStack {
            Text("No command matches \u{201C}\(query)\u{201D}")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.bottom, 16)
    }

    private func runHighlighted() {
        guard results.indices.contains(highlighted) else { return }
        onRun(results[highlighted].action)
    }
}

