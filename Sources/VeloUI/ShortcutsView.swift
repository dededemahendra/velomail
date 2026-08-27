import SwiftUI
import VeloCore

/// The whole keymap on one card.
///
/// Every row is read out of `KeyboardEngine`, so this cannot come to disagree
/// with the keys it claims to document. The palette teaches shortcuts one at a
/// time as you look things up; this is for the sitting down and learning them.
struct ShortcutsView: View {
    let onClose: () -> Void

    /// The bound actions, under the same headings as the palette.
    private var sections: [(group: CommandSection, rows: [(title: String, keys: String)])] {
        let titles = Dictionary(
            CommandRegistry.v1.commands.filter { $0.argument == nil }
                .map { ($0.action, $0) },
            uniquingKeysWith: { first, _ in first })
        let bound = KeyboardEngine.everyShortcut.compactMap { shortcut -> (CommandSection, String, String)? in
            // Only what the palette also names: an action with no command has
            // no words to put beside its key.
            guard let command = titles[shortcut.action] else { return nil }
            return (command.group, command.title, shortcut.keys)
        }
        return CommandSection.allCases.compactMap { group in
            let rows = bound.filter { $0.0 == group }
                .map { (title: $0.1, keys: $0.2) }
                .sorted { $0.title < $1.title }
            return rows.isEmpty ? nil : (group, rows)
        }
    }

    /// Splits the sections into two columns of roughly equal height.
    ///
    /// A grid aligns by row, so a section of one sat beside a section of seven
    /// and left the gap between them. Balancing by row count keeps the card to
    /// one screen, which is the only reason it is a card and not a list.
    static func columns<Section>(_ sections: [Section],
                                 rows: (Section) -> Int) -> (left: [Section], right: [Section]) {
        let heights = sections.map { rows($0) + 1 }   // +1 for each heading
        let total = heights.reduce(0, +)
        // Every split point tried rather than filling the left column until it
        // looks full: taking them in turn overshoots on the one tall section,
        // which is how GO ended up alone against three short groups.
        var best = 0
        var bestGap = Int.max
        var running = 0
        for index in 0...sections.count {
            let gap = abs(running - (total - running))
            // Ties go to the later split, so a lone section sits on the left
            // rather than leaving the left column empty.
            if gap <= bestGap {
                bestGap = gap
                best = index
            }
            if index < sections.count { running += heights[index] }
        }
        return (Array(sections.prefix(best)), Array(sections.suffix(from: best)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard shortcuts").font(.headline)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            ScrollView {
                let split = Self.columns(sections) { $0.rows.count }
                HStack(alignment: .top, spacing: 28) {
                    column(split.left)
                    column(split.right)
                }
                .padding(20)
            }
        }
        .frame(width: 660, height: 640)
    }

    private func column(_ sections: [(group: CommandSection,
                                      rows: [(title: String, keys: String)])]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections, id: \.group) { section in
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.group.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.rows, id: \.title) { row in
                        HStack(spacing: 10) {
                            Text(row.title).font(.system(size: 12))
                            Spacer(minLength: 12)
                            Text(row.keys)
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary.opacity(0.5),
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(row.title), \(row.keys)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
