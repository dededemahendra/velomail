import Testing
import Foundation

/// Guards against the way this regresses: a control drawn as an icon, or one
/// whose visible label is hidden, and nobody notices because it looks right.
@Suite struct AccessibilityCoverageTests {
    private func source(_ name: String) throws -> String {
        // Walks up from this file to the package root, so it does not depend on
        // where the tests were run from.
        var directory = URL(fileURLWithPath: #filePath)
        while directory.lastPathComponent != "velomail", directory.pathComponents.count > 1 {
            directory.deleteLastPathComponent()
        }
        return try String(contentsOf: directory
            .appendingPathComponent("Sources/VeloUI/\(name)"), encoding: .utf8)
    }

    @Test func everyHiddenLabelHasASpokenOneNearby() throws {
        // `labelsHidden()` removes the accessibility label as well as the
        // visible one, which is the trap: the control still looks fine.
        for file in ["SettingsView.swift", "ComposeView.swift"] {
            let text = try source(file)
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("labelsHidden()") {
                // Either the picker carries a real title or a label follows.
                let window = lines[max(0, index - 3)...min(lines.count - 1, index + 3)]
                    .joined(separator: "\n")
                #expect(window.contains("accessibilityLabel")
                        || window.contains("accessibilityElement")
                        || window.range(of: #"Picker\("[A-Z]"#, options: .regularExpression) != nil,
                        "\(file):\(index + 1) hides its label and says nothing")
            }
        }
    }

    @Test func iconOnlyButtonsInTheComposerSayWhatTheyDo() throws {
        let text = try source("ComposeView.swift")
        // Every Image(systemName:) inside a Button label needs a name; the
        // toolbar's come from one helper, so it is that helper being checked.
        #expect(text.contains(".accessibilityLabel(name)"))
    }
}
