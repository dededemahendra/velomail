import Testing
import Foundation
import SwiftUI
import AppKit
import VeloCore
@testable import VeloUI

/// The one seam unit tests cannot reach: `ComposeViewModel` rewrites `body`
/// from inside its own `didSet`, while SwiftUI's `TextEditor` is mid-write to
/// that same binding. Whether the editor honours a re-entrant change is
/// SwiftUI's business, not ours, so it is exercised against a real hosted view
/// rather than assumed.
///
/// Typing is driven with `insertText` on the live `NSTextView`, which goes
/// through the same text system a keystroke does — no Accessibility permission
/// and no synthetic events.
@MainActor
@Suite struct ComposeEditorExpansionTests {
    @Test func typingAShortcutIntoTheRealEditorExpandsIt() throws {
        let (model, host) = try makeHostedCompose()
        let textView = try #require(findTextView(in: host))

        type(";thx ", into: textView)

        #expect(model.body == "Thanks so much.")
        // And the editor shows what the model holds, rather than the two
        // drifting apart on screen.
        #expect(textView.string == "Thanks so much.")
        #expect(!textView.string.contains(";thx"))
    }

    @Test func typingAnUnknownShortcutLeavesTheEditorAlone() throws {
        // The control: it proves `insertText` really does drive the binding, so
        // the expansion above is not passing vacuously.
        let (model, host) = try makeHostedCompose()
        let textView = try #require(findTextView(in: host))

        type(";nope ", into: textView)

        #expect(model.body == ";nope ")
        #expect(textView.string == ";nope ")
    }

    // MARK: - Internals

    private func makeHostedCompose() throws -> (ComposeViewModel, NSHostingView<ComposeView>) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let library = SnippetLibrary(snippets: [
            Snippet(name: "Thanks", shortcut: "thx", body: "Thanks so much."),
        ])
        let model = ComposeViewModel(
            outbound: OutboundService(writer: DeadWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", library: library)
        model.startNew()

        let view = ComposeView(model: model,
                               assistant: AssistantViewModel(assistant: MailAssistant(provider: nil)),
                               onSend: {}, onCancel: {})
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 700, height: 460)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        pump()
        return (model, host)
    }

    /// One character at a time, because that is what typing is — and only a
    /// single inserted character can trigger an expansion.
    private func type(_ text: String, into textView: NSTextView) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
        pump()
    }

    private func pump(_ seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }
}

private struct DeadWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError("unused") }
}
