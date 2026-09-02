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

    /// The tick and the unread dot are blank on most rows and must stay
    /// visible anyway -- they hold the gutter open, and a gutter that collapses
    /// moves the whole row sideways as mail is read.
    ///
    /// Named rather than found by "a blank field": the snippet and the label
    /// chip are also blank sometimes and are legitimately hidden, and an
    /// earlier version of this swept them up and broke when the chip learned
    /// to hide itself.
    @Test func theBlankTickAndDotAreStillVisible() {
        let row = laidOutRow(unread: false)
        let gutter = allFields(in: row).filter {
            $0.identifier.map(ThreadRowView.gutterIdentifiers.contains) ?? false
        }

        #expect(gutter.count == 2)
        #expect(gutter.allSatisfy { !$0.isHidden })
        #expect(gutter.allSatisfy { $0.frame.width > 0 })
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

    // MARK: - The label chip

    /// Rendering rows at 300, 380 and 520pt found the chip in three different
    /// states for the same data: absent, "Re", and "In...". It shared the top
    /// line with the sender and lost, because it is the first thing told to
    /// give up space -- and a chip reduced to two letters reads as a rendering
    /// fault, not as a label.
    ///
    /// It now sits on the snippet line, where the only thing it competes with
    /// is preview text that was already being truncated.

    private func chipField(in view: NSView) -> NSTextField? {
        allFields(in: view).first { $0.identifier == ThreadRowView.labelIdentifier }
    }

    private func rowWith(label: String, sender: String, width: CGFloat) -> ThreadRowView {
        let subject = MailThread(id: "t", sender: sender, snippet: "a snippet worth reading",
                                 lastMessageDate: Date(timeIntervalSince1970: 0),
                                 isUnread: false, hasAttachments: false, labelIDs: ["INBOX"])
        let row = ThreadRowView(thread: subject, isMarked: false,
                                name: MailFormatting.displayName(sender),
                                dateText: "Yesterday", previewLines: 1,
                                labels: label.isEmpty ? [] : [label])
        row.frame = NSRect(x: 0, y: 0, width: width, height: 64)
        row.layoutSubtreeIfNeeded()
        return row
    }

    /// The case that produced "In..." -- a long sender beside a long label.
    @Test func aLongSenderNoLongerSqueezesTheLabelToNothing() throws {
        let row = rowWith(label: "Invoices to pay this quarter",
                          sender: "A Very Long Organisation Name Indeed Pty Ltd <x@y.com>",
                          width: 520)
        let chip = try #require(chipField(in: row))

        #expect(!chip.isHidden)
        #expect(chip.frame.width > 40,
                "the chip got \(chip.frame.width)pt, which shows about two letters")
    }

    /// And the sender keeps its own space, which is what putting the chip up
    /// there cost in the first place.
    @Test func theSenderIsNotTruncatedByALongLabel() throws {
        let withLabel = rowWith(label: "Invoices to pay this quarter",
                                sender: "Peta Bilston <peta@x.com>", width: 380)
        let without = rowWith(label: "", sender: "Peta Bilston <peta@x.com>", width: 380)

        let a = try #require(textField("Peta Bilston", in: withLabel))
        let b = try #require(textField("Peta Bilston", in: without))
        #expect(abs(a.frame.width - b.frame.width) < 0.5,
                "a label cost the sender \(b.frame.width - a.frame.width)pt")
    }

    @Test func aRowWithNoLabelShowsNoChip() throws {
        let row = rowWith(label: "", sender: "Peta Bilston <peta@x.com>", width: 380)
        #expect(chipField(in: row)?.isHidden == true)
    }

    /// The invariant, whatever the widths happen to be: the chip shows what it
    /// was given, or it is not there at all. Anything between is a smudge.
    ///
    /// Checked across widths and label lengths because the first attempt at
    /// this passed every test in the suite and still came out as a lone "..."
    /// in the running app -- a spacer view was quietly winning the space.
    @Test func theChipIsEitherFullyReadableOrAbsent() throws {
        for width in [300.0, 380.0, 450.0, 520.0] {
            for label in ["Updates", "Clients", "Receipts", "Invoices to pay this quarter"] {
                let row = rowWith(label: label, sender: "Hostinger <h@x.com>", width: width)
                let chip = try #require(chipField(in: row))
                guard !chip.isHidden else { continue }

                let needed = chip.intrinsicContentSize.width
                let note = "at \(width)pt the chip '\(chip.stringValue)' got \(chip.frame.width)pt of the \(needed)pt it needs"
                #expect(chip.frame.width >= needed - 0.5, "\(note)")
            }
        }
    }

    // MARK: - Read against unread

    /// Told plainly: "a little confused about which email are already opened or
    /// still unread".
    ///
    /// Three things separated the two states -- a 7pt dot, the sender's weight,
    /// and the sender's colour -- and all three live on one short line. The
    /// snippet, which is the widest text on the row and the thing the eye
    /// actually lands on, was drawn identically either way. A row you had read
    /// and a row you had not looked nearly the same.

    private func row(unread: Bool) -> ThreadRowView {
        let subject = MailThread(id: "t", sender: "Cloudflare <ops@cloudflare.com>",
                                 snippet: "the snippet",
                                 lastMessageDate: Date(timeIntervalSince1970: 0),
                                 isUnread: unread, hasAttachments: false, labelIDs: ["INBOX"])
        let view = ThreadRowView(thread: subject, isMarked: false, name: "Cloudflare",
                                 dateText: "Yesterday", previewLines: 1)
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 64)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func brightness(_ field: NSTextField?) -> CGFloat {
        guard let colour = field?.textColor?.usingColorSpace(.deviceRGB) else { return -1 }
        return colour.brightnessComponent * colour.alphaComponent
    }

    @Test func anUnreadRowIsBrighterAcrossTheWholeRowNotJustTheSender() throws {
        let unread = row(unread: true), read = row(unread: false)

        let unreadSender = brightness(textField("Cloudflare", in: unread))
        let readSender = brightness(textField("Cloudflare", in: read))
        #expect(unreadSender > readSender, "the sender does not dim when read")

        // The one that was missing, and the one that matters most: it is the
        // widest thing on the row.
        let unreadSnippet = brightness(snippetField(in: unread))
        let readSnippet = brightness(snippetField(in: read))
        #expect(unreadSnippet > readSnippet, "the snippet reads the same either way")
    }

    @Test func theSenderIsHeavierWhenUnread() throws {
        let heavy = try #require(textField("Cloudflare", in: row(unread: true))).font
        let light = try #require(textField("Cloudflare", in: row(unread: false))).font
        #expect(heavy != light)
    }

    /// The dot is the only signal that is present-or-absent rather than a
    /// shade, so it has to be big enough to notice.
    @Test func theUnreadDotIsLargeEnoughToSee() throws {
        let dot = try #require(allFields(in: row(unread: true)).first {
            $0.identifier == ThreadRowView.gutterIdentifiers[1]
        })
        #expect(!dot.stringValue.isEmpty)
        #expect((dot.font?.pointSize ?? 0) >= 8)
    }

    @Test func aReadRowShowsNoDotAtAll() throws {
        let dot = try #require(allFields(in: row(unread: false)).first {
            $0.identifier == ThreadRowView.gutterIdentifiers[1]
        })
        #expect(dot.stringValue.isEmpty)
    }
}
