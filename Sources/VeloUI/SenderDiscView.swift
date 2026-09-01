import AppKit
import VeloCore

/// A coloured initial standing in for a sender, for the AppKit list.
///
/// The transcript already had one of these as a SwiftUI view (`SenderDisc`),
/// but the list is an `NSTableView` and could not use it, so rows went without
/// any sender mark at all. The colour and the letter both come from
/// `MessageAddressing`, so one correspondent is the same disc in the list and
/// in the thread rather than two unrelated decorations.
final class SenderDiscView: NSView {
    /// Matches the row's text block rather than the transcript's 26pt disc: a
    /// list row is two lines and a disc taller than them pushes the rows apart.
    static let size: CGFloat = 30

    let fill: NSColor
    private let letter: String

    /// Keyed on the name the row displays, not on the thread's sender. In Sent
    /// the row shows the recipient, and a disc drawn from the sender would put
    /// the reader's own initial beside every row in the list.
    init(name: String) {
        self.letter = MessageAddressing.initial(for: name)
        // The same hue, saturation and brightness the transcript's disc uses;
        // measured for contrast against the white letter rather than picked.
        self.fill = NSColor(hue: MessageAddressing.hue(for: name),
                            saturation: 0.52, brightness: 0.62, alpha: 1)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = Self.size / 2

        let label = NSTextField(labelWithString: letter)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // The name is spoken beside it; a letter read aloud is noise.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
}
