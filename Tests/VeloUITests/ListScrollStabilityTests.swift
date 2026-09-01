import Testing
import AppKit
import SwiftUI
import Foundation
import VeloCore
@testable import VeloUI

/// Stands in for the app object the real list reads its rows through, and for
/// whatever republishes while the reader is scrolling -- in the app, the
/// once-a-second sync-status poll.
@MainActor
private final class Ticker: ObservableObject {
    @Published var count = 0
    func name(of thread: MailThread) -> String { MailFormatting.displayName(thread.sender) }
    func date(of thread: MailThread) -> String { MailFormatting.relativeDate(thread.lastMessageDate) }
}

/// The arrangement in `RootView.mailSurface`: the list sits in a body with
/// something that redraws on its own, and takes its row text through closures
/// that capture the app.
///
/// Both halves matter. A body that re-runs is what reaches the list at all, and
/// the closures are why it reaches it: SwiftUI skips `updateNSView` when a
/// representable's stored values all compare equal, and a closure that captures
/// never does -- each body evaluation allocates it afresh. Written here with
/// non-capturing closures, this harness passes whether or not the bug is
/// present, because `updateNSView` is never called.
private struct Harness: View {
    @ObservedObject var ticker: Ticker
    let sections: [ThreadSection]
    let selectedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            MessageListView(sections: sections, selectedIndex: selectedIndex,
                            markedIndices: [],
                            name: { ticker.name(of: $0) },
                            date: { ticker.date(of: $0) },
                            onSelect: { _ in }, onOpen: {})
            // The status bar, standing in: it reads the ticking value, so a
            // tick invalidates this body and the list is rebuilt with it.
            Text(verbatim: "\(ticker.count)")
        }
    }
}

/// The bug end to end, in the view the reader actually touches.
///
/// `MessageListViewTests` covers the follow-the-selection decision on its own.
/// This drives the real `NSScrollView` SwiftUI builds: scroll away from the
/// selection, republish something unrelated, and the viewport must stay where
/// it was put. Before the fix it jumped back to the selected row on every tick.
@MainActor
@Suite struct ListScrollStabilityTests {
    private func threads(_ count: Int) -> [MailThread] {
        (0..<count).map {
            MailThread(id: "t\($0)", snippet: "snippet \($0)",
                       lastMessageDate: Date(timeIntervalSince1970: TimeInterval(1_000 - $0)),
                       isUnread: false, hasAttachments: false, labelIDs: ["INBOX"])
        }
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let found = scrollView(in: child) { return found }
        }
        return nil
    }

    private func pump(_ times: Int = 6) {
        for _ in 0..<times {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private struct MountFailure: Error { let message: String }

    /// Hosts the list offscreen. The window is returned so it outlives the test
    /// body; releasing it mid-test tears the hierarchy down under the assertions.
    private func mount(selected: Int?, rows: Int = 60) throws
        -> (list: NSScrollView, ticker: Ticker, window: NSWindow) {
        let ticker = Ticker()
        let host = NSHostingView(rootView: Harness(ticker: ticker,
                                                   sections: InboxSections.split(threads(rows)),
                                                   selectedIndex: selected))
        host.frame = NSRect(x: 0, y: 0, width: 380, height: 300)
        // An offscreen view has no appearance, and dynamic system colours then
        // resolve to nothing. Irrelevant to geometry, but it keeps the rows off
        // an unusual path while they lay out.
        host.appearance = NSAppearance(named: .aqua)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        pump()

        guard let list = scrollView(in: host) else {
            throw MountFailure(message: "SwiftUI built no NSScrollView for the list")
        }
        return (list, ticker, window)
    }

    /// Moves the viewport the way a trackpad would, and reports where it landed.
    @discardableResult
    private func scroll(_ list: NSScrollView, toY y: CGFloat) -> CGFloat {
        list.contentView.scroll(to: NSPoint(x: 0, y: y))
        list.reflectScrolledClipView(list.contentView)
        pump(2)
        return list.contentView.bounds.origin.y
    }

    /// Ten seconds of the once-a-second poll.
    private func tick(_ ticker: Ticker, times: Int = 10) {
        for _ in 0..<times {
            ticker.count += 1
            pump(2)
        }
    }

    @Test func anUnrelatedRedrawLeavesTheViewportWhereTheReaderPutIt() throws {
        // Selection at the top, so scrolling down takes it off-screen -- the
        // situation in the recording: the selected row leaves the viewport and
        // the next redraw drags it back.
        let mounted = try mount(selected: 0)
        let landed = scroll(mounted.list, toY: 900)
        #expect(landed > 100, "the list must actually be scrollable for this to mean anything")

        tick(mounted.ticker)

        #expect(mounted.list.contentView.bounds.origin.y == landed)
        withExtendedLifetime(mounted.window) {}
    }

    @Test func aRedrawDoesNotDisturbAListNobodyHasScrolled() throws {
        let mounted = try mount(selected: 0)
        let resting = mounted.list.contentView.bounds.origin.y

        tick(mounted.ticker)

        #expect(mounted.list.contentView.bounds.origin.y == resting)
        withExtendedLifetime(mounted.window) {}
    }

    /// The control. Without this the suite above could pass on a list that
    /// never rendered, or on redraws that never reached the list at all.
    @Test func theTickReachesTheListAndTheListHasRows() throws {
        let mounted = try mount(selected: 0)
        let table = mounted.list.documentView as? NSTableView
        #expect(table?.numberOfRows == 60)

        // Moving the selection must still drag the viewport with it -- that is
        // what j/k depends on, and it is the behaviour the fix narrows rather
        // than removes. It also proves a redraw reaches `updateNSView` at all.
        scroll(mounted.list, toY: 0)
        let host = mounted.window.contentView as? NSHostingView<Harness>
        host?.rootView = Harness(ticker: mounted.ticker,
                                 sections: InboxSections.split(threads(60)),
                                 selectedIndex: 45)
        pump(6)

        #expect(table?.selectedRow == 45)
        #expect(mounted.list.contentView.bounds.origin.y > 100,
                "the viewport must follow the selection when it moves")
        withExtendedLifetime(mounted.window) {}
    }
}
