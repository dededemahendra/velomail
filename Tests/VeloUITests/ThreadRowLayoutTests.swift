import Testing
import AppKit
import Foundation
import VeloCore
@testable import VeloUI

/// What survives of the sender-disc attempt.
///
/// The list deliberately has no avatar: the transcript has one, where a long
/// thread between three people is genuinely easier to follow in colour, and the
/// list does not need it. But building one exposed a real defect underneath --
/// the row moved sideways as mail was read -- and that is worth keeping fixed
/// whether or not anything sits in front of it.
@MainActor
@Suite struct ThreadRowLayoutTests {
    private func laidOutRow(unread: Bool) -> ThreadRowView {
        let subject = MailThread(id: "t1", sender: "Cloudflare <ops@cloudflare.com>",
                                 snippet: "the snippet",
                                 lastMessageDate: Date(timeIntervalSince1970: 0),
                                 isUnread: unread, hasAttachments: false, labelIDs: ["INBOX"])
        let row = ThreadRowView(thread: subject, isMarked: false, name: "Cloudflare",
                                dateText: "Today", previewLines: 1)
        row.frame = NSRect(x: 0, y: 0, width: 380, height: 64)
        row.layoutSubtreeIfNeeded()
        return row
    }

    private func textField(_ text: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == text { return field }
        for child in view.subviews {
            if let found = textField(text, in: child) { return found }
        }
        return nil
    }

    private func leading(of text: String, in row: ThreadRowView) throws -> CGFloat {
        let field = try #require(textField(text, in: row))
        return field.convert(field.bounds, to: row).minX
    }

    /// The unread dot is an empty text field on a read row. Left to size itself
    /// it collapsed, and the sender beside it slid 7pt left -- so a row visibly
    /// shifted at the moment it was read, which is the moment the eye is on it.
    @Test func theSenderDoesNotMoveWhenTheRowIsRead() throws {
        let unread = try leading(of: "Cloudflare", in: laidOutRow(unread: true))
        let read = try leading(of: "Cloudflare", in: laidOutRow(unread: false))

        #expect(abs(unread - read) < 0.5,
                "sender at \(unread) unread, \(read) read")
    }

    /// The list is not to grow an avatar again by accident. The transcript's
    /// `SenderDisc` is a SwiftUI view and cannot appear here, but this pins the
    /// intent rather than leaving it to be rediscovered.
    @Test func theListRowCarriesNoAvatar() {
        let row = laidOutRow(unread: false)

        func isDisc(_ view: NSView) -> Bool {
            view.layer?.cornerRadius ?? 0 > 0 || view.subviews.contains(where: isDisc)
        }
        #expect(!isDisc(row))
    }

    // MARK: - Reuse

    /// `NSTableView` is built around recycling row views, and this table used
    /// none of it: `viewFor` constructed a fresh `ThreadRowView` -- five text
    /// fields, a stack and constraints -- every time it was asked. Measured at
    /// 1.08ms a row, which is ~12ms to refill a screen and another 1.08ms for
    /// every row exposed while scrolling.
    ///
    /// These pin the two halves of the fix: a view can be reconfigured, and
    /// reconfiguring does not quietly rebuild it.

    private func described(_ row: ThreadRowView) -> [String] {
        var found: [String] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField { found.append(field.stringValue) }
            view.subviews.forEach(walk)
        }
        walk(row)
        return found
    }

    private func subviewCount(_ view: NSView) -> Int {
        1 + view.subviews.reduce(0) { $0 + subviewCount($1) }
    }

    private func thread(_ id: String, sender: String, snippet: String,
                        unread: Bool = false) -> MailThread {
        MailThread(id: id, sender: sender, snippet: snippet,
                   lastMessageDate: Date(timeIntervalSince1970: 0),
                   isUnread: unread, hasAttachments: false, labelIDs: ["INBOX"])
    }

    @Test func aRowCanBeGivenNewContentWithoutBeingRebuilt() {
        let row = ThreadRowView()
        row.configure(thread: thread("a", sender: "Alice <a@x.com>", snippet: "first"),
                      isMarked: false, name: "Alice", dateText: "Today",
                      previewLines: 1, labels: [])
        let built = subviewCount(row)
        #expect(described(row).contains("Alice"))

        row.configure(thread: thread("b", sender: "Bob <b@x.com>", snippet: "second"),
                      isMarked: false, name: "Bob", dateText: "Yesterday",
                      previewLines: 1, labels: [])

        let text = described(row)
        #expect(text.contains("Bob"))
        #expect(text.contains("second"))
        // The whole point: no second copy of the hierarchy underneath.
        #expect(subviewCount(row) == built,
                "reconfiguring grew the view from \(built) to \(subviewCount(row)) subviews")
    }

    /// Everything the row shows has to be reset, not only the parts that
    /// happened to change. A recycled view carries the last thread's state, so
    /// anything left unset shows the wrong mail -- a star or an unread dot from
    /// a conversation three screens away.
    @Test func reconfiguringClearsWhatTheLastThreadLeftBehind() {
        let starred = MailThread(id: "a", sender: "Alice <a@x.com>", snippet: "first",
                                 lastMessageDate: Date(timeIntervalSince1970: 0),
                                 isUnread: true, hasAttachments: true,
                                 labelIDs: ["INBOX", "STARRED"])
        let row = ThreadRowView()
        row.configure(thread: starred, isMarked: true, name: "Alice", dateText: "Today",
                      previewLines: 1, labels: ["Invoices"])
        #expect(described(row).contains { $0.contains("\u{2605}") })

        row.configure(thread: thread("b", sender: "Bob <b@x.com>", snippet: "second"),
                      isMarked: false, name: "Bob", dateText: "Yesterday",
                      previewLines: 1, labels: [])

        let text = described(row)
        #expect(!text.contains { $0.contains("\u{2605}") }, "star survived: \(text)")
        #expect(!text.contains { $0.contains("\u{2713}") }, "tick survived: \(text)")
        #expect(!text.contains("Invoices"), "label survived: \(text)")
        #expect(!text.contains { $0.contains("\u{1F4CE}") }, "paperclip survived: \(text)")
    }

    /// And the table has to be told the view is reusable, or it will never
    /// offer one back.
    @Test func theRowCarriesAReuseIdentifier() {
        let row = ThreadRowView()
        row.configure(thread: thread("a", sender: "Alice <a@x.com>", snippet: "s"),
                      isMarked: false, name: "Alice", dateText: "Today",
                      previewLines: 1, labels: [])
        #expect(row.identifier == ThreadRowView.reuseIdentifier)
    }

    /// A thread whose snippet is empty left a blank second line: the row drew a
    /// sender and then a void the height of a line of text. Found by rendering
    /// rows at three widths with deliberately awkward data -- an empty snippet
    /// is what a message with only an attachment, or an empty body, produces.
    @Test func aThreadWithNoSnippetDoesNotLeaveAnEmptyLine() {
        let bare = MailThread(id: "t", sender: "Alice <a@x.com>", snippet: "",
                              lastMessageDate: Date(timeIntervalSince1970: 0),
                              isUnread: false, hasAttachments: true, labelIDs: ["INBOX"])
        let row = ThreadRowView(thread: bare, isMarked: false, name: "Alice",
                                dateText: "Today", previewLines: 1)
        row.frame = NSRect(x: 0, y: 0, width: 380, height: 64)
        row.layoutSubtreeIfNeeded()

        let snippet = snippetField(in: row)
        #expect(snippet?.isHidden == true, "an empty snippet is still taking up a line")
    }

    /// And a row that has one still shows it.
    @Test func aThreadWithASnippetStillShowsIt() throws {
        let row = laidOutRow(unread: false)
        let snippet = try #require(snippetField(in: row))
        #expect(!snippet.isHidden)
        #expect(snippet.stringValue == "the snippet")
    }

    /// The tick and the unread dot are blank on most rows and must not be
    /// swept up by the same rule -- they hold the gutter open.
    @Test func theBlankTickAndDotAreStillVisible() {
        let row = laidOutRow(unread: false)
        let blanks = allFields(in: row).filter { $0.stringValue.isEmpty && $0.identifier != ThreadRowView.snippetIdentifier }
        #expect(!blanks.isEmpty)
        #expect(blanks.allSatisfy { !$0.isHidden })
    }

    private func allFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField { found.append(field) }
        for child in view.subviews { found.append(contentsOf: allFields(in: child)) }
        return found
    }

    private func snippetField(in view: NSView) -> NSTextField? {
        allFields(in: view).first { $0.identifier == ThreadRowView.snippetIdentifier }
    }
}
