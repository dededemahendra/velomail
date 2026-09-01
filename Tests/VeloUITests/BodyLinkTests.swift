import Testing
import WebKit
import Foundation
@testable import VeloUI

/// Clicking a link or a button in a message did nothing at all.
///
/// The body's web view had a navigation delegate that only measured the
/// document's height. With nothing deciding what a click means, a link either
/// tried to replace the message in place or -- more often -- was killed by the
/// content blocker, which blocks every `http(s)` load precisely so trackers
/// cannot fetch. The reader pressed a button and the app sat there.
///
/// The rules are here rather than in the delegate because what should happen is
/// a judgement about hostile input, and it is worth being able to state it
/// exactly: mail HTML is written by strangers.
@Suite struct BodyLinkTests {
    private func decide(_ address: String?, _ type: WKNavigationType = .linkActivated,
                        mainFrame: Bool = true) -> BodyLink.Decision {
        BodyLink.decide(url: address.flatMap(URL.init(string:)),
                        type: type, isMainFrame: mainFrame)
    }

    // MARK: - What a click should do

    @Test func aClickedLinkGoesToTheBrowser() {
        #expect(decide("https://example.com/offer") == .open(URL(string: "https://example.com/offer")!))
        #expect(decide("http://example.com") == .open(URL(string: "http://example.com")!))
    }

    /// The "buttons" in marketing mail are links, and usually `target="_blank"`,
    /// which is why they felt different from ordinary links: they went through
    /// a separate WebKit path that had no delegate at all.
    @Test func aFormSubmissionIsAlsoADeliberateAction() {
        #expect(decide("https://example.com/subscribe", .formSubmitted)
                    == .open(URL(string: "https://example.com/subscribe")!))
    }

    @Test func mailtoAndTelAreHandedOnToo() {
        #expect(decide("mailto:someone@example.com") == .open(URL(string: "mailto:someone@example.com")!))
        #expect(decide("tel:+61400000000") == .open(URL(string: "tel:+61400000000")!))
    }

    // MARK: - What must never reach the system

    /// A message is written by a stranger. Handing an arbitrary scheme to
    /// `NSWorkspace` is handing a stranger the ability to launch things.
    @Test func exoticSchemesAreRefusedRatherThanOpened() {
        #expect(decide("javascript:alert(1)") == .cancel)
        #expect(decide("file:///etc/passwd") == .cancel)
        #expect(decide("data:text/html,<b>x</b>") == .cancel)
        #expect(decide("ftp://example.com") == .cancel)
        #expect(decide("x-devious-app://run") == .cancel)
    }

    // MARK: - What must still be allowed

    /// The message itself. `loadHTMLString` with no base URL navigates to
    /// `about:blank`, and refusing that renders a blank pane.
    @Test func theMessageDocumentItselfLoads() {
        #expect(decide("about:blank", .other) == .allow)
        #expect(decide(nil, .other) == .allow)
    }

    /// A subframe is not a click. The blocker already stops remote loads, and
    /// cancelling these would break legitimate inline content.
    @Test func subframesAreLeftToTheContentBlocker() {
        #expect(decide("https://example.com/frame", .other, mainFrame: false) == .allow)
    }

    /// A redirect the sender wrote is not the reader asking for anything. It
    /// must not open a browser window on its own -- that would make merely
    /// reading a message launch whatever the sender chose.
    @Test func aRedirectTheSenderInitiatedIsRefused() {
        #expect(decide("https://tracker.example.com/beacon", .other) == .cancel)
    }
}

/// A stand-in for the thing WebKit hands the delegate. Its properties are
/// read-only, so the only way to pose a question to the real delegate is to
/// override them.
private final class FakeNavigationAction: WKNavigationAction {
    private let url: URL
    private let kind: WKNavigationType

    init(_ address: String, _ kind: WKNavigationType = .linkActivated) {
        self.url = URL(string: address)!
        self.kind = kind
    }

    override var request: URLRequest { URLRequest(url: url) }
    override var navigationType: WKNavigationType { kind }
    /// Nil is what WebKit passes for a `target="_blank"` link, and what the
    /// delegate has to treat as the main frame.
    override var targetFrame: WKFrameInfo? { nil }
}

/// The decision above is only worth anything if the web view asks it.
///
/// This project's recurring fault is a capability that exists, is tested, and
/// is reached by nothing -- which is exactly what the message body was: a
/// navigation delegate that measured the document's height and answered no
/// other question.
@MainActor
@Suite struct BodyLinkWiringTests {
    private func coordinator() -> (MessageBodyView.Coordinator, () -> [URL]) {
        let coordinator = MessageBodyView.Coordinator()
        let opened = Box()
        coordinator.openLink = { opened.urls.append($0) }
        return (coordinator, { opened.urls })
    }

    private final class Box { var urls: [URL] = [] }

    @Test func clickingALinkHandsItToTheBrowserAndDoesNotNavigate() async {
        let (coordinator, opened) = coordinator()
        let webView = WKWebView()

        var policy: WKNavigationActionPolicy?
        coordinator.webView(webView,
                            decidePolicyFor: FakeNavigationAction("https://example.com/offer")) {
            policy = $0
        }

        #expect(opened().map(\.absoluteString) == ["https://example.com/offer"])
        // The message must stay on screen: the reader is reading it.
        #expect(policy == .cancel)
    }

    @Test func theDocumentItselfIsAllowedThrough() async {
        let (coordinator, opened) = coordinator()
        var policy: WKNavigationActionPolicy?
        coordinator.webView(WKWebView(),
                            decidePolicyFor: FakeNavigationAction("about:blank", .other)) {
            policy = $0
        }

        #expect(policy == .allow)
        #expect(opened().isEmpty)
    }

    @Test func aRefusedSchemeIsNeverHandedToTheSystem() async {
        let (coordinator, opened) = coordinator()
        var policy: WKNavigationActionPolicy?
        coordinator.webView(WKWebView(),
                            decidePolicyFor: FakeNavigationAction("file:///etc/passwd")) {
            policy = $0
        }

        #expect(policy == .cancel)
        #expect(opened().isEmpty, "handed a stranger's file URL to the OS")
    }

    /// The `target="_blank"` path, which is what the buttons in marketing mail
    /// use and which never reaches the navigation delegate.
    @Test func aLinkAskingForItsOwnWindowStillOpens() {
        let (coordinator, opened) = coordinator()

        let made = coordinator.webView(WKWebView(), createWebViewWith: WKWebViewConfiguration(),
                                       for: FakeNavigationAction("https://example.com/button"),
                                       windowFeatures: WKWindowFeatures())

        #expect(opened().map(\.absoluteString) == ["https://example.com/button"])
        #expect(made == nil, "a second web view would open a browser inside the message")
    }
}
