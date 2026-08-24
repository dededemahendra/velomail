import SwiftUI
import AppKit
import VeloCore

/// One local `NSEvent` monitor translating key-downs into `KeyInput`.
///
/// Returning the event when unhandled is the important part: swallowing
/// everything would stop text fields receiving keys, so typing "e" in Compose
/// would archive the inbox instead of writing a letter.
struct KeyMonitor: NSViewRepresentable {
    let handle: (KeyInput) -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install(handle)
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handle: ((KeyInput) -> Bool)?
        private var monitor: Any?

        func install(_ handle: @escaping (KeyInput) -> Bool) {
            self.handle = handle
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let input = KeyMonitor.translate(event) else { return event }
                return self.handle?(input) == true ? nil : event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    /// AppKit key-down → engine `KeyInput`. Only Command and Shift matter to the
    /// v1 keymap, so other modifiers are ignored rather than blocking a match.
    static func translate(_ event: NSEvent) -> KeyInput? {
        var modifiers: KeyInput.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }

        switch event.keyCode {
        case 36, 76: return KeyInput(.enter, modifiers)     // Return, keypad Enter
        case 53: return KeyInput(.escape, modifiers)
        default:
            // "/" opens search, so punctuation cannot be filtered out wholesale.
            guard let character = event.charactersIgnoringModifiers?.first,
                  character.isLetter || character.isNumber || character == "/" else { return nil }
            return KeyInput(.character(character), modifiers)
        }
    }
}
