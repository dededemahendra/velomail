import SwiftUI
import AppKit
import VeloCore

/// The body editor.
///
/// An `NSTextView` rather than SwiftUI's `TextEditor` for one reason: a
/// formatting button has to know what is selected, and `TextEditor` does not
/// say. Everything else about it is deliberately plain.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Applied on the next update, then cleared. A command rather than a call,
    /// because the toolbar lives outside the view that owns the selection.
    @Binding var pending: MarkdownFormatting.Style?
    var font: NSFont = .systemFont(ofSize: 13)

    /// Where the first character sits, from the editor's own edges.
    ///
    /// Exposed so the placeholder drawn over the top can use the same numbers
    /// rather than a pair that happen to look close. AppKit adds a
    /// `lineFragmentPadding` of its own on top of `textContainerInset`, which
    /// is what made the caret and the placeholder disagree.
    static let textOrigin = NSSize(width: 20, height: 10)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.font = font
        textView.isRichText = false           // the marks are the formatting
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.textOrigin
        // Zeroed so the inset above is the whole story; left at its default 5
        // there are two paddings to keep in step and only one of them is
        // visible in this file.
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        // Only when it actually differs: writing the string back on every
        // update would fight the person typing and reset the caret.
        if textView.string != text { textView.string = text }

        if let style = pending {
            context.coordinator.apply(style, in: textView)
            DispatchQueue.main.async { pending = nil }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Rewrites the text and puts the selection back where the writer
        /// expects it -- around the words they marked, or where the part they
        /// still have to supply goes.
        func apply(_ style: MarkdownFormatting.Style, in textView: NSTextView) {
            let selection = textView.selectedRange()
            let result = MarkdownFormatting.apply(
                style, to: textView.string,
                selecting: selection.location..<(selection.location + selection.length))

            // Through the text system rather than by assignment, so one press
            // is one undo step.
            let whole = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: whole, replacementString: result.text) {
                textView.textStorage?.replaceCharacters(in: whole, with: result.text)
                textView.didChangeText()
            }
            textView.setSelectedRange(NSRange(location: result.selection.lowerBound,
                                              length: result.selection.count))
            parent.text = textView.string
        }
    }
}
