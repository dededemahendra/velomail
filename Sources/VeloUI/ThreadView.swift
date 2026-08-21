import SwiftUI
import WebKit
import VeloCore

/// Renders a message body in a `WKWebView` with remote content blocked.
///
/// Mail HTML is hostile: remote images are tracking pixels, and scripts have no
/// business running. The configuration below is the sandbox the v1 design asks
/// for -- no JavaScript, and a content rule that blocks every off-document load.
struct MessageBodyView: NSViewRepresentable {
    let message: Message

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        installRemoteContentBlocker(on: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(document(for: message), baseURL: nil)
    }

    /// Blocks every remote load. Applied asynchronously, so the body is only
    /// loaded once the rules are in place -- otherwise the first render could
    /// still fetch trackers.
    private func installRemoteContentBlocker(on webView: WKWebView) {
        let rules = """
        [{"trigger":{"url-filter":".*","load-type":["third-party","first-party"]},
          "action":{"type":"block"}}]
        """
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "velo-block-remote", encodedContentRuleList: rules
        ) { list, _ in
            if let list { webView.configuration.userContentController.add(list) }
        }
    }

    /// Wraps the body so it inherits the system font and respects dark mode,
    /// rather than rendering as unstyled 1990s HTML on white.
    private func document(for message: Message) -> String {
        let body = message.bodyHTML ?? "<pre>\(escaped(message.bodyText ?? ""))</pre>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body { font: -apple-system-body, system-ui, sans-serif; font-size: 14px;
                 line-height: 1.55; margin: 0; padding: 20px 24px;
                 color: canvastext; background: transparent;
                 word-wrap: break-word; }
          img { max-width: 100%; height: auto; }
          pre { white-space: pre-wrap; font: inherit; }
          blockquote { margin: 0 0 0 12px; padding-left: 12px;
                       border-left: 2px solid color-mix(in srgb, canvastext 25%, transparent);
                       color: color-mix(in srgb, canvastext 65%, transparent); }
          a { color: -apple-system-blue; }
        </style></head><body>\(body)</body></html>
        """
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// A thread: header, then the newest message's body.
struct ThreadView: View {
    let thread: MailThread
    let messages: [Message]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = messages.last {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(message.sender).font(.callout)
                        Spacer()
                        Text(message.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !message.recipients.isEmpty {
                        Text("to \(message.recipients.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                Divider()
                MessageBodyView(message: message)
            } else {
                Text("No messages").foregroundStyle(.secondary).padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
