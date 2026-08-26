import SwiftUI
import WebKit
import VeloCore

/// Renders a message body in a `WKWebView` with remote content blocked.
///
/// Mail HTML is hostile: remote images are tracking pixels and scripts have no
/// business running. JavaScript is off, and a content rule blocks remote loads.
struct MessageBodyView: NSViewRepresentable {
    let message: Message
    /// The message's own parts, so `cid:` references in the body resolve.
    var attachments: [MailAttachment] = []

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView, document: document)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(document)
    }

    /// Compiles the blocker once, then renders. Rendering genuinely waits for
    /// the rules: compilation is async, so loading immediately would let the
    /// first message fetch trackers before the blocker existed.
    @MainActor
    final class Coordinator {
        private enum State {
            case compiling
            case ready
            case unavailable
        }

        private var state: State = .compiling
        private weak var webView: WKWebView?
        private var pending: String?

        /// Remote schemes only. A catch-all ".*" also matches the inline
        /// document `loadHTMLString` creates, which blocks the message itself
        /// and renders a blank pane.
        private static let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """

        func attach(_ webView: WKWebView, document: String) {
            self.webView = webView
            pending = document

            guard let store = WKContentRuleListStore.default() else {
                state = .unavailable
                flush()
                return
            }
            store.compileContentRuleList(forIdentifier: "velo-block-remote",
                                         encodedContentRuleList: Self.rules) { [weak self] list, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let list {
                        self.webView?.configuration.userContentController.add(list)
                        self.state = .ready
                    } else {
                        self.state = .unavailable
                    }
                    self.flush()
                }
            }
        }

        func render(_ document: String) {
            pending = document
            flush()
        }

        private func flush() {
            guard let webView, let document = pending else { return }
            switch state {
            case .compiling:
                return                      // held until the blocker exists
            case .ready:
                pending = nil
                webView.loadHTMLString(document, baseURL: nil)
            case .unavailable:
                // Without a blocker, rendering raw mail HTML would leak
                // tracking pixels. Strip what can fetch, rather than choosing
                // between a blank pane and a privacy hole.
                pending = nil
                webView.loadHTMLString(MessageBodyView.stripRemoteContent(from: document), baseURL: nil)
            }
        }
    }

    /// Last-resort fallback: drop every element that can pull a remote URL.
    static func stripRemoteContent(from document: String) -> String {
        var stripped = document
        for tag in ["img", "iframe", "video", "audio", "object", "embed", "source", "script"] {
            stripped = remove(tag, from: stripped)
        }
        return stripped
    }

    /// Tags that may legitimately carry their own bytes. Blocking exists to
    /// stop the sender learning a message was opened; a `data:` URI makes no
    /// request, so stripping one costs the reader a picture and protects
    /// nothing. Scripts are never in this list, whatever their scheme.
    private static let mayCarryOwnBytes: Set<String> = ["img", "source"]

    private static func carriesOwnBytes(_ tag: Substring) -> Bool {
        tag.localizedCaseInsensitiveContains("src=\"data:")
            || tag.localizedCaseInsensitiveContains("src='data:")
    }

    private static func remove(_ tag: String, from html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "</?\(tag)\\b[^>]*>",
                                                   options: .caseInsensitive) else { return html }
        let keepsOwnBytes = mayCarryOwnBytes.contains(tag)
        var out = ""
        var last = html.startIndex
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            out += html[last..<range.lowerBound]
            if keepsOwnBytes, carriesOwnBytes(html[range]) { out += html[range] }
            last = range.upperBound
        }
        out += html[last...]
        return out
    }

    private var document: String { Self.document(for: message, attachments: attachments) }

    /// Wraps the body so it inherits the system font and respects dark mode,
    /// rather than rendering as unstyled 1990s HTML on white.
    static func document(for message: Message, attachments: [MailAttachment] = []) -> String {
        let raw = message.bodyHTML ?? "<pre>\(escaped(message.bodyText ?? ""))</pre>"
        // Before the styling, so a substituted data: URI is inside the document
        // the content rules are applied to rather than bolted on afterwards.
        let body = InlineImages.embed(raw, using: attachments)
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          /* font-family, not the `font` shorthand: `font: -apple-system-body,
             system-ui, ...` is invalid and the whole rule gets dropped, which
             silently falls back to Times. */
          body { font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
                 font-size: 14px;
                 line-height: 1.55; margin: 0; padding: 20px 24px;
                 color: canvastext; background: transparent;
                 word-wrap: break-word; }
          img { max-width: 100%; height: auto; }
          pre { white-space: pre-wrap; font-family: inherit; font-size: inherit; }
          blockquote { margin: 0 0 0 12px; padding-left: 12px;
                       border-left: 2px solid color-mix(in srgb, canvastext 25%, transparent);
                       color: color-mix(in srgb, canvastext 65%, transparent); }
          a { color: -apple-system-blue; }
        </style></head><body>\(body)</body></html>
        """
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// A thread as a transcript: every message, newest expanded, older ones
/// collapsed to a line that expands on click.
struct ThreadView: View {
    let thread: MailThread
    let messages: [Message]
    let isExpanded: (String) -> Bool
    let onToggle: (String) -> Void
    let attachments: (String) -> [MailAttachment]
    @ObservedObject var attachmentModel: AttachmentViewModel
    let onUnsubscribe: () -> Void

    /// Whether this thread can be left. Parsed rather than merely present: a
    /// header we cannot act on must not put a button on screen that does
    /// nothing when pressed.
    static func canUnsubscribe(from messages: [Message]) -> Bool {
        messages.contains { Unsubscribe.preferred(in: $0.listUnsubscribe ?? "") != nil }
    }

    var body: some View {
        if messages.isEmpty {
            Text("No messages")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // The subject belongs to the thread, not to each message, so it
                // sits above the transcript rather than repeating in every card.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(subject)
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                    // Only when the sender said how to leave. An always-visible
                    // button that usually does nothing is worse than none.
                    if Self.canUnsubscribe(from: messages) {
                        Button(action: onUnsubscribe) {
                            Label("Unsubscribe", systemImage: "hand.raised")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Unsubscribe (u)")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
                Divider()

                // GeometryReader so the transcript can be told to fill the pane.
                // Inside a ScrollView, maxHeight: .infinity means "as tall as
                // the content", which left the body stopping partway down with a
                // hard edge that reads as a rendering fault.
                GeometryReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                MessageCard(message: message,
                                            isExpanded: isExpanded(message.id),
                                            isOnly: messages.count == 1,
                                            attachments: attachments(message.id),
                                            attachmentModel: attachmentModel,
                                            onToggle: { onToggle(message.id) })
                                // No rule under the last message: it would draw
                                // a line across empty space.
                                if index < messages.count - 1 { Divider() }
                            }
                        }
                        .frame(minHeight: proxy.size.height, alignment: .top)
                    }
                }
            }
        }
    }

    private var subject: String {
        let subject = messages.last?.subject ?? ""
        return subject.isEmpty ? "(no subject)" : subject
    }
}

/// One message: a header that is always shown and always clickable, plus the
/// body when expanded.
private struct MessageCard: View {
    let message: Message
    let isExpanded: Bool
    let isOnly: Bool
    let attachments: [MailAttachment]
    @ObservedObject var attachmentModel: AttachmentViewModel
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // Display name only: a full "Name <addr>" wraps to two
                        // lines and makes the transcript look ragged.
                        Text(MailFormatting.displayName(message.sender))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(message.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if isExpanded {
                        // The full address earns its space only once opened.
                        Text(addressLine)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        // Collapsed: one line of what it said, so the thread can
                        // be skimmed without opening every message.
                        Text(preview)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A one-message thread has nothing to collapse into.
            .disabled(isOnly)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if isExpanded {
                if !attachments.isEmpty {
                    AttachmentStrip(attachments: attachments, model: attachmentModel)
                }
                // Fills what is left of the pane. A fixed height leaves a hard
                // seam where the web view stops and the window background
                // resumes, which reads as a rendering fault.
                MessageBodyView(message: message, attachments: attachments)
                    .frame(minHeight: 260, maxHeight: .infinity)
            }
        }
    }

    private var addressLine: String {
        var line = message.sender
        if !message.recipients.isEmpty {
            line += " → " + message.recipients.map(MailFormatting.displayName).joined(separator: ", ")
        }
        return line
    }

    private var preview: String {
        let text = message.bodyText
            ?? MessageBodyView.stripRemoteContent(from: message.bodyHTML ?? "")
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
