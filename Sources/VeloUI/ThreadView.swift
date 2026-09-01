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
    /// Set once the reader has asked for this message's pictures. Off by
    /// default and never remembered: a sender learns a message was opened the
    /// moment one loads, so it stays a per-message decision.
    var loadsRemoteImages = false
    /// Set to the document's own height once it has laid out, so the body can
    /// be as tall as the message instead of scrolling inside a fixed box.
    var onMeasure: (CGFloat) -> Void = { _ in }
    /// Where a `mailto:` in the body goes. Into this app's composer, not the
    /// system's idea of a mail client.
    var onComposeTo: (MailtoLink) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = PassThroughWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        // Also the UI delegate: a `target="_blank"` link -- which is what the
        // buttons in marketing mail almost always are -- never reaches the
        // navigation delegate at all. WebKit asks for a new web view instead,
        // and with nobody to ask, the click did nothing.
        webView.uiDelegate = context.coordinator
        context.coordinator.onMeasure = onMeasure
        context.coordinator.onComposeTo = onComposeTo
        context.coordinator.attach(webView, document: currentDocument,
                                   allowingRemote: loadsRemoteImages)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMeasure = onMeasure
        context.coordinator.onComposeTo = onComposeTo
        context.coordinator.render(currentDocument, allowingRemote: loadsRemoteImages)
    }

    /// Compiles the blocker once, then renders. Rendering genuinely waits for
    /// the rules: compilation is async, so loading immediately would let the
    /// first message fetch trackers before the blocker existed.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private enum State {
            case compiling
            case ready
            case unavailable
        }

        private var state: State = .compiling
        private weak var webView: WKWebView?
        private var pending: String?
        private var allowsRemote = false
        /// What is already on screen. SwiftUI calls `updateNSView` for reasons
        /// that have nothing to do with this message -- a sync tick republishes
        /// the whole tree every second -- and reloading the page each time made
        /// it flash and threw away wherever the reader had scrolled to.
        private var loaded: String?
        var onMeasure: (CGFloat) -> Void = { _ in }
        /// How a link leaves the app. Injected so a test never launches a
        /// browser.
        var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
        var onComposeTo: (MailtoLink) -> Void = { _ in }

        /// Decides what a click in the message means.
        ///
        /// Mail is not a browser: a link goes to the reader's browser rather
        /// than replacing the message they are reading. Without this the body
        /// had no policy at all -- a click either tried to navigate in place or
        /// was swallowed by the content blocker, which refuses every remote
        /// load so trackers cannot fetch. Either way, nothing happened.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            switch BodyLink.decide(url: navigationAction.request.url,
                                   type: navigationAction.navigationType,
                                   isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true) {
            case .allow:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case let .open(url):
                openLink(url)
                decisionHandler(.cancel)
            case let .compose(link):
                onComposeTo(link)
                decisionHandler(.cancel)
            }
        }

        /// A link asking for a window of its own. Returning nil refuses the
        /// window; the destination has already been handed to the browser.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // `targetFrame` is nil here -- that absence is what makes it a
            // request for a new window -- so the frame is not in question.
            switch BodyLink.decide(url: navigationAction.request.url,
                                   type: navigationAction.navigationType, isMainFrame: true) {
            case let .open(url): openLink(url)
            case let .compose(link): onComposeTo(link)
            case .allow, .cancel: break
            }
            return nil
        }

        /// Asks the page how tall it turned out.
        ///
        /// `evaluateJavaScript` still runs with `allowsContentJavaScript` off:
        /// that setting stops the *sender's* scripts, not the host's. So the
        /// measurement works without giving mail HTML a way to run anything.
        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
                guard let height = (value as? NSNumber)?.doubleValue, height > 0 else { return }
                Task { @MainActor [weak self] in self?.onMeasure(CGFloat(height)) }
            }
        }

        /// Remote schemes only. A catch-all ".*" also matches the inline
        /// document `loadHTMLString` creates, which blocks the message itself
        /// and renders a blank pane.
        private static let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """

        func attach(_ webView: WKWebView, document: String, allowingRemote: Bool) {
            self.webView = webView
            pending = document
            allowsRemote = allowingRemote

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

        func render(_ document: String, allowingRemote: Bool) {
            guard document != loaded || allowingRemote != allowsRemote else { return }
            pending = document
            allowsRemote = allowingRemote
            flush()
        }

        private func flush() {
            guard let webView, let document = pending else { return }
            switch state {
            case .compiling:
                return                      // held until the blocker exists
            case .ready:
                pending = nil
                // The rules are removed for this web view only, and only once
                // the reader has asked. Every other message keeps its blocker.
                if allowsRemote {
                    webView.configuration.userContentController.removeAllContentRuleLists()
                }
                loaded = document
                webView.loadHTMLString(document, baseURL: nil)
            case .unavailable:
                // Without a blocker, rendering raw mail HTML would leak
                // tracking pixels. Strip what can fetch, rather than choosing
                // between a blank pane and a privacy hole -- unless the reader
                // has explicitly asked for this message's pictures.
                pending = nil
                loaded = document
                webView.loadHTMLString(
                    allowsRemote ? document : MessageBodyView.stripRemoteContent(from: document),
                    baseURL: nil)
            }
        }
    }

    /// A web view that does not eat scroll gestures.
///
/// The message body is sized to its own content and the transcript around it
/// does the scrolling. Without this the web view swallows the wheel and the
/// thread will not move: a scroller inside a scroller, where the inner one has
/// nothing left to scroll.
private final class PassThroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // The message is already as tall as its content, so this view has
        // nothing of its own to scroll and the transcript should move instead.
        //
        // Re-dispatching the event to the enclosing scroll view does nothing:
        // AppKit's scrolling is driven by the event reaching it through the
        // normal routing, and a phase-carrying event handed over by hand is
        // simply dropped. Moving the clip view is what actually scrolls it.
        guard let scrollView = enclosingScrollView, let document = scrollView.documentView else {
            super.scrollWheel(with: event)
            return
        }

        let clip = scrollView.contentView
        // A trackpad reports pixels; a wheel reports lines, which are worth
        // about a line of text each.
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 16

        var origin = clip.bounds.origin
        origin.y -= delta                       // the document view is flipped
        let limit = max(0, document.frame.height - clip.bounds.height)
        origin.y = min(max(0, origin.y), limit)

        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
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

    private var currentDocument: String {
        Self.document(for: message, attachments: attachments, allowingRemote: loadsRemoteImages)
    }

    /// Wraps the body so it inherits the system font and respects dark mode,
    /// rather than rendering as unstyled 1990s HTML on white.
    static func document(for message: Message, attachments: [MailAttachment] = [],
                         allowingRemote: Bool = false) -> String {
        // Mail the sender wrote as HTML is painted on the surface they wrote it
        // for; the plain-text fallback is ours to style, so it follows the app.
        let text = (message.bodyText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let html = message.bodyHTML, !html.isEmpty else {
            // A message can genuinely arrive with nothing in it -- a bare
            // attachment, a calendar invitation, a bounce. Rendering that as an
            // empty white pane reads as a bug in this app rather than as an
            // empty message.
            guard !text.isEmpty else {
                return wrap(plainText: "<p class=\"velo-empty\">This message has no text.</p>")
            }
            return wrap(plainText: "<pre>\(escaped(text))</pre>")
        }
        // Before the styling, so a substituted data: URI is inside the document
        // the content rules are applied to rather than bolted on afterwards.
        return wrap(html: InlineImages.embed(html, using: attachments),
                    hidingRemoteImages: !allowingRemote)
    }

    /// The same body view, set up for quoting inside a composer.
    ///
    /// Remote images stay blocked whatever the reader's standing preference
    /// says. That preference is about mail being read; a tracking pixel in a
    /// quote would fire while the reply is still being written, telling the
    /// sender the message was opened when it has not even been read.
    static func previewOfQuote(_ message: Message,
                               attachments: [MailAttachment] = [],
                               onMeasure: @escaping (CGFloat) -> Void = { _ in }) -> MessageBodyView {
        MessageBodyView(message: message, attachments: attachments,
                        loadsRemoteImages: false, onMeasure: onMeasure)
    }

    /// True when the message points at pictures that live on a server.
    ///
    /// Those are what the content blocker stops, and the reader deserves to be
    /// told rather than left looking at gaps.
    static func hasRemoteImages(_ message: Message) -> Bool {
        guard let html = message.bodyHTML else { return false }
        for quote in ["\"", "'"] where html.localizedCaseInsensitiveContains("src=\(quote)http") {
            return true
        }
        return false
    }

    /// Wraps sender-authored HTML on a light page.
    ///
    /// `color-scheme: light` rather than `light dark`: the sender chose their
    /// colours for a white background, and letting the system flip only the
    /// parts they left unstyled produces dark text on a dark strip through half
    /// the message. The surface fills the pane, so a short message does not
    /// leave the rest of it a different colour.
    private static func wrap(html body: String, hidingRemoteImages: Bool) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light; }
          html { height: 100%; }
          body { font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
                 font-size: 14px;
                 line-height: 1.55; margin: 0; padding: 20px 24px;
                 min-height: 100%; box-sizing: border-box;
                 color: #1d1d1f; background: #ffffff;
                 word-wrap: break-word; }
          \(sharedRules)
          \(hidingRemoteImages ? Self.hiddenRemoteImages : "")
        </style></head><body>\(body)</body></html>
        """
    }

    /// A blocked image still lays out: an empty bordered box that reads as a
    /// broken message rather than as a choice made on the reader's behalf.
    /// Scoped to remote ones -- a picture carrying its own bytes fetches
    /// nothing, so there is no reason to hide it.
    private static let hiddenRemoteImages = """
          img[src^="http"] { display: none; }
    """

    /// Wraps our own plain-text rendering, which can and should match the app
    /// around it.
    private static func wrap(plainText body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          html { height: 100%; }
          /* font-family, not the `font` shorthand: `font: -apple-system-body,
             system-ui, ...` is invalid and the whole rule gets dropped, which
             silently falls back to Times. */
          body { font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
                 font-size: 14px;
                 line-height: 1.55; margin: 0; padding: 20px 24px;
                 min-height: 100%; box-sizing: border-box;
                 color: #1d1d1f; background: #ffffff;
                 word-wrap: break-word; }
          @media (prefers-color-scheme: dark) {
            body { color: #e8e8ed; background: #1e1e1e; }
          }
          \(sharedRules)
        </style></head><body>\(body)</body></html>
        """
    }

    private static let sharedRules = """
          img { max-width: 100%; height: auto; }
          pre { white-space: pre-wrap; font-family: inherit; font-size: inherit; }
          .velo-empty { opacity: 0.5; font-style: italic; }
          blockquote { margin: 0 0 0 12px; padding-left: 12px;
                       border-left: 2px solid color-mix(in srgb, currentColor 25%, transparent);
                       color: color-mix(in srgb, currentColor 65%, transparent); }
          a { color: #0b6fd4; }
    """


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
    /// The standing answer to "load this message's pictures?", set once in the
    /// command palette rather than asked on every message.
    var alwaysLoadsImages = false
    /// Named labels, so a thread can say what it was filed as. Filing was
    /// possible and invisible before this.
    var knownLabels: [MailLabel] = []
    /// The reader's own address, so a message to them reads "to me".
    var identity: String = ""
    let onUnsubscribe: () -> Void
    /// Where a `mailto:` in a message body goes.
    var onComposeTo: (MailtoLink) -> Void = { _ in }

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
                    // The list marks a starred thread and the thread itself did
                    // not, so opening one lost the only sign it was kept.
                    if thread.labelIDs.contains("STARRED") {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Starred")
                    }
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
                        .accessibilityHint("Asks the sender to stop mailing you")
                        .buttonStyle(.borderless)
                        .help("Unsubscribe (u)")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
                if !detail.isEmpty {
                    // Under the subject rather than beside it: a subject is
                    // long and this must not push it into a second line.
                    let chips = ThreadDetail.chips(on: thread.labelIDs, known: knownLabels)
                    HStack(spacing: 6) {
                        ForEach(chips.shown) { label in
                            Text(label.displayName)
                                .font(.system(size: 10, weight: .medium))
                                // Never squashed: without this the words wrap
                                // inside their own capsules.
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.tint.opacity(0.16), in: Capsule())
                        }
                        if chips.extra > 0 {
                            Text("+\(chips.extra)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        if let count = ThreadDetail.messageCount(messages.count) {
                            Text(count).font(.system(size: 10)).foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                        if attachmentCount > 0 {
                            Label("\(attachmentCount)", systemImage: "paperclip")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24).padding(.bottom, 10)
                    .accessibilityElement(children: .ignore)
                    // Spelled out rather than combined: a listener hearing
                    // "plus four" learns nothing, and has no chips to look at.
                    .accessibilityLabel(detail.joined(separator: ", "))
                }

                Divider()

                // GeometryReader so the transcript can be told to fill the pane.
                // Inside a ScrollView, maxHeight: .infinity means "as tall as
                // the content", which left the body stopping partway down with a
                // hard edge that reads as a rendering fault.
                GeometryReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(TranscriptRows.build(messages).enumerated()),
                                    id: \.element.id) { index, row in
                                if let heading = row.dayHeading {
                                    // The date once, above the messages it
                                    // covers, rather than on every line.
                                    Text(heading.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(0.5)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 24)
                                        .padding(.top, index == 0 ? 10 : 18)
                                        .padding(.bottom, 4)
                                }
                                MessageCard(row: row,
                                            isExpanded: isExpanded(row.message.id),
                                            isOnly: messages.count == 1,
                                            attachments: attachments(row.message.id),
                                            attachmentModel: attachmentModel,
                                            alwaysLoadsImages: alwaysLoadsImages,
                                            paneHeight: proxy.size.height,
                                            identity: identity,
                                            onToggle: { onToggle(row.message.id) },
                                            onComposeTo: onComposeTo)
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

    /// Everything the header has to add beyond the subject, in words.
    ///
    /// Also what a listener hears: every label, not the three the row had room
    /// to draw, since "plus four" tells them nothing and they have no chips to
    /// look at.
    private var detail: [String] {
        var parts = ThreadDetail.labels(on: thread.labelIDs, known: knownLabels)
            .map { "Filed in \($0.displayName)" }
        if let count = ThreadDetail.messageCount(messages.count) { parts.append(count) }
        if attachmentCount > 0 {
            parts.append("\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s")")
        }
        return parts
    }

    private var attachmentCount: Int {
        messages.reduce(0) { $0 + attachments($1.id).count }
    }

    private var subject: String {
        let subject = messages.last?.subject ?? ""
        return subject.isEmpty ? "(no subject)" : subject
    }
}

/// One message: a header that is always shown and always clickable, plus the
/// body when expanded.
private struct MessageCard: View {
    let row: TranscriptRows.Row
    var message: Message { row.message }
    let isExpanded: Bool
    let isOnly: Bool
    let attachments: [MailAttachment]
    @ObservedObject var attachmentModel: AttachmentViewModel
    /// Set from the app-wide preference, so someone who has decided once is
    /// not asked again on every message.
    var alwaysLoadsImages = false
    /// How tall the pane is, so an unmeasured body can fill it.
    let paneHeight: CGFloat
    /// The reader's own address, so a message addressed to them can say "to
    /// me" rather than reading their address back at them.
    var identity: String = ""
    let onToggle: () -> Void
    /// Where a `mailto:` in this message body goes.
    var onComposeTo: (MailtoLink) -> Void = { _ in }

    /// Per message and never persisted: asking once should not sign the reader
    /// up to be counted by every sender afterwards.
    @State private var showsRemoteImages = false

    /// This message's answer, or the standing one.
    private var loadsImages: Bool { showsRemoteImages || alwaysLoadsImages }

    /// How tall the body turned out, once the page has said. Until then the
    /// body fills the pane: a short one leaves the rest showing the
    /// transcript's own dark ground, which is the flash of black on opening a
    /// message -- and it is not the body that is black.
    @State private var bodyHeight: CGFloat?


    /// The colour the message is about to paint itself, so the wait for it is
    /// invisible. HTML mail is authored for white; our plain-text rendering
    /// follows the app.
    private var bodyBackground: Color {
        message.bodyHTML != nil ? .white : Color(nsColor: .textBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    // A disc rather than a picture: there is no avatar to
                    // fetch, and a coloured initial is enough to tell one
                    // correspondent from another down a long thread. Held at
                    // the run's first message, so a run reads as one block
                    // rather than a column of repeated badges.
                    if row.showsSender {
                        SenderDisc(sender: message.sender)
                    } else {
                        Color.clear.frame(width: SenderDisc.size, height: 1)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        // Named only when it changes. Twelve alerts from one
                        // sender do not need the name twelve times, and the
                        // eye should land on what actually differs.
                        if row.showsSender {
                            // Display name only: a full "Name <addr>" wraps to
                            // two lines and makes the transcript look ragged.
                            Text(MailFormatting.displayName(message.sender))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                        Spacer()
                        // The clock only; the day is on the heading above.
                        // The full stamp lives in the tooltip: a transcript
                        // said "Yesterday" and "17.28" and nowhere at all what
                        // date that actually was.
                        Text(row.time)
                            .font(.caption).foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .help(MailFormatting.fullStamp(message.date))
                            .accessibilityLabel(MailFormatting.fullStamp(message.date))
                    }
                    if isExpanded {
                        // The address earns its space only once opened -- and
                        // only the address: the name is in bold directly above
                        // and saying it twice is repetition, not detail.
                        HStack(spacing: 6) {
                            Text(MessageAddressing.address(of: message.sender))
                                .lineLimit(1).truncationMode(.middle)
                            if let to = MessageAddressing.recipients(
                                to: message.recipients, cc: message.cc, identity: identity) {
                                // Tertiary, not quaternary: a separator you
                                // cannot see is not a separator.
                                Text("\u{00B7}").foregroundStyle(.tertiary)
                                Text(to).lineLimit(1)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    } else if row.showsPreview {
                        // Collapsed: one line of what it said, so the thread can
                        // be skimmed without opening every message. Left out
                        // when it would repeat the line above word for word.
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(row.showsSender
                                             ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                    }
                }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A one-message thread has nothing to collapse into.
            .disabled(isOnly)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MailFormatting.messageDescription(
                message, time: row.time, isExpanded: isExpanded))
            .accessibilityHint(isOnly ? "" : (isExpanded ? "Collapses this message"
                                                         : "Opens this message"))
            .padding(.horizontal, 24)
            .padding(.vertical, row.showsSender ? 10 : 6)

            if isExpanded {
                if !attachments.isEmpty {
                    AttachmentStrip(attachments: attachments, model: attachmentModel)
                }
                // Fills what is left of the pane. A fixed height leaves a hard
                // seam where the web view stops and the window background
                // resumes, which reads as a rendering fault.
                if MessageBodyView.hasRemoteImages(message) && !loadsImages {
                    RemoteImageBar { showsRemoteImages = true }
                }
                MessageBodyView(message: message, attachments: attachments,
                                loadsRemoteImages: loadsImages,
                                onMeasure: { bodyHeight = max($0, 60) },
                                onComposeTo: onComposeTo)
                    .frame(height: bodyHeight ?? paneHeight)
                    // Painted behind the web view, which is transparent until
                    // WebKit's first paint. Without it the window's own dark
                    // ground shows through for half a second every time a
                    // message is opened, which reads as a flash of breakage.
                    .background(bodyBackground)
            }
        }
    }

    private var preview: String {
        let text = message.bodyText
            ?? MessageBodyView.stripRemoteContent(from: message.bodyHTML ?? "")
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
