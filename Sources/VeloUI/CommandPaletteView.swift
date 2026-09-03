import SwiftUI
import VeloCore

/// The Cmd+K palette. Filtering and ranking come from `CommandRegistry`; this
/// only renders them.
struct CommandPaletteView: View {
    let registry: CommandRegistry
    /// The last few commands run, floated to the top when nothing is typed.
    var recents: [MailAction] = []
    let onRun: (Command) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private var results: [Command] { registry.matches(query, recents: recents) }

    /// Where a heading goes and what it says, by row.
    ///
    /// Computed against the flat result list rather than nesting the rows in
    /// sections, so the arrow keys keep walking one continuous index and a
    /// heading cannot be landed on.
    private var headings: [Int: String] {
        guard query.isEmpty else { return [:] }   // typed results are ranked, not grouped
        var found: [Int: String] = [:]
        var seen = Set<String>()
        let recentCount = min(recents.count, results.count)
        for (index, command) in results.enumerated() {
            let title = index < recentCount ? "Recent" : command.group.rawValue
            if !seen.contains(title) {
                found[index] = title
                seen.insert(title)
            }
        }
        return found
    }

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
                // The arrows belong to the list, not to the caret. Focus has
                // to live in the field -- it is the thing being typed into --
                // so the list can only be driven from here. Same form the
                // composer's recipient suggestions use, which is known to
                // reach the key before the caret does.
                .onKeyPress(phases: .down, action: handleKey)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            listBody
                // Follows the highlight, so holding Down does not walk the
                // selection off the bottom of a list of fifty commands.
                .onChange(of: highlighted) { _, index in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
        }
    }

    /// Arrow keys move the highlight; everything else is the field's.
    ///
    /// Control-N and Control-P as well, which cost nothing and are what a
    /// keyboard-first app's users reach for without thinking.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        switch (press.key, press.modifiers.contains(.control)) {
        case (.downArrow, _): return move(1)
        case (.upArrow, _): return move(-1)
        case (KeyEquivalent("n"), true): return move(1)
        case (KeyEquivalent("p"), true): return move(-1)
        default: return .ignored
        }
    }

    /// Moves the highlight, and says the key was ours so the caret stays put.
    private func move(_ offset: Int) -> KeyPress.Result {
        highlighted = WrappingIndex.moved(from: highlighted, by: offset, count: results.count)
        return .handled
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                let headings = headings
                ForEach(Array(results.enumerated()), id: \.offset) { index, command in
                    if let heading = headings[index] {
                        Text(heading.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 2 : 10)
                            .padding(.bottom, 3)
                            .accessibilityAddTraits(.isHeader)
                    }
                    row(command, isHighlighted: index == highlighted)
                        .contentShape(Rectangle())
                        .id(index)
                        .onTapGesture { onRun(command) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        // Driven from the keyboard, so a scroller is one more thing drawn over
        // the glass for no one.
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
        onRun(results[highlighted])
    }
}

