import Testing
import AppKit
import Foundation
import VeloCore
@testable import VeloUI

/// The list interleaves section headers with threads, so a table row is no
/// longer a cursor index. These cover that mapping, which the eye cannot check
/// and which silently selects the wrong thread when it is wrong.
@MainActor
@Suite struct MessageListViewTests {
    private func thread(_ id: String, labels: [String] = ["INBOX"]) -> MailThread {
        MailThread(id: id, snippet: id, lastMessageDate: Date(timeIntervalSince1970: 0),
                   isUnread: false, hasAttachments: false, labelIDs: labels)
    }

    private func list(_ threads: [MailThread], selected: Int? = nil,
                      marked: Set<Int> = []) -> MessageListView {
        MessageListView(sections: InboxSections.split(threads), selectedIndex: selected,
                        markedIndices: marked,
                        name: { MailFormatting.displayName($0.sender) },
                        date: { MailFormatting.relativeDate($0.lastMessageDate) },
                        onSelect: { _ in }, onOpen: {})
    }

    private func described(_ rows: [MessageListView.Row]) -> [String] {
        rows.map {
            switch $0 {
            case let .header(title): return "#\(title)"
            case let .thread(thread, index): return "\(index):\(thread.id)"
            }
        }
    }

    @Test func oneSectionGetsNoHeader() {
        // A lone "Other" above an ordinary inbox is noise; the split is meant to
        // disappear when nothing is important.
        #expect(described(list([thread("a"), thread("b")]).rows) == ["0:a", "1:b"])
    }

    @Test func twoSectionsGetHeaders() {
        let rows = list([thread("a"), thread("b", labels: ["INBOX", "STARRED"])]).rows
        #expect(described(rows) == ["#Important", "0:b", "#Other", "1:a"])
    }

    @Test func flatIndicesSkipTheHeadersSoTheCursorStaysFlat() {
        let rows = list([thread("a"), thread("b", labels: ["INBOX", "STARRED"]),
                         thread("c"), thread("d", labels: ["INBOX", "IMPORTANT"])]).rows

        // Four threads, two headers, and the indices still run 0...3 in display
        // order — which is exactly what `inbox.threads` holds.
        #expect(described(rows) == ["#Important", "0:b", "1:d", "#Other", "2:a", "3:c"])
    }

    @Test func emptyInboxHasNoRows() {
        #expect(list([]).rows.isEmpty)
    }

    @Test func theCoordinatorMapsAThreadIndexToItsTableRow() {
        let view = list([thread("a"), thread("b", labels: ["INBOX", "STARRED"]), thread("c")])
        let coordinator = view.makeCoordinator()

        // Thread 0 is under the first header, so it is table row 1.
        #expect(coordinator.row(forThread: 0) == 1)
        #expect(coordinator.row(forThread: 2) == 4)
        #expect(coordinator.row(forThread: 9) == nil)
    }

    @Test func headersAreNotSelectable() {
        let view = list([thread("a"), thread("b", labels: ["INBOX", "STARRED"])])
        let coordinator = view.makeCoordinator()
        let table = NSTableView()

        // Selecting a header would hand the cursor an index that means nothing.
        #expect(!coordinator.tableView(table, shouldSelectRow: 0))
        #expect(coordinator.tableView(table, shouldSelectRow: 1))
        #expect(coordinator.tableView(table, isGroupRow: 0))
        #expect(!coordinator.tableView(table, isGroupRow: 1))
    }

    @Test func aHeaderRowIsShorterThanAThreadRow() {
        let view = list([thread("a"), thread("b", labels: ["INBOX", "STARRED"])])
        let coordinator = view.makeCoordinator()
        let table = NSTableView()

        #expect(coordinator.tableView(table, heightOfRow: 0)
                    < coordinator.tableView(table, heightOfRow: 1))
    }

    // MARK: - Following the selection

    /// The bug these cover: `updateNSView` runs on every published change
    /// anywhere in the app, and the sync status ticks once a second. Scrolling
    /// to the selection on all of them dragged the list back under the reader's
    /// hands about a second after every manual scroll.

    @Test func theViewportFollowsASelectionItHasNotFollowedYet() {
        let view = list([thread("a"), thread("b"), thread("c")], selected: 1)
        let coordinator = view.makeCoordinator()

        #expect(coordinator.shouldFollowSelection(toRow: 1))
    }

    @Test func theViewportDoesNotFollowTheSameSelectionTwice() {
        let view = list([thread("a"), thread("b"), thread("c")], selected: 1)
        let coordinator = view.makeCoordinator()

        #expect(coordinator.shouldFollowSelection(toRow: 1))
        // The second update is the once-a-second status tick, not the reader
        // moving. Following it here is the scroll-snapback bug.
        #expect(!coordinator.shouldFollowSelection(toRow: 1))
        #expect(!coordinator.shouldFollowSelection(toRow: 1))
    }

    @Test func theViewportFollowsWhenTheSelectionMoves() {
        let view = list([thread("a"), thread("b"), thread("c")], selected: 1)
        let coordinator = view.makeCoordinator()

        #expect(coordinator.shouldFollowSelection(toRow: 1))
        // j/k must still drag the viewport with it, or the cursor walks
        // off-screen.
        #expect(coordinator.shouldFollowSelection(toRow: 2))
    }

    @Test func mailArrivingAboveTheSelectionDoesNotMoveTheViewport() {
        let view = list([thread("b"), thread("c")], selected: 0)
        let coordinator = view.makeCoordinator()
        #expect(coordinator.shouldFollowSelection(toRow: 0))

        // A sync lands a newer thread on top: the reader's thread is the same
        // conversation at a different row, and they have not asked to go
        // anywhere. Keyed on the row alone this would scroll.
        let after = list([thread("a"), thread("b"), thread("c")], selected: 1)
        coordinator.parent = after
        coordinator.rows = after.rows

        #expect(!coordinator.shouldFollowSelection(toRow: 1))
    }

    @Test func reselectingAThreadAfterADeselectFollowsItAgain() {
        let view = list([thread("a"), thread("b"), thread("c")], selected: 1)
        let coordinator = view.makeCoordinator()
        #expect(coordinator.shouldFollowSelection(toRow: 1))

        // Clearing the list drops the selection entirely; coming back to the
        // same thread is a fresh request to go there.
        coordinator.forgetFollowedSelection()

        #expect(coordinator.shouldFollowSelection(toRow: 1))
    }
}
