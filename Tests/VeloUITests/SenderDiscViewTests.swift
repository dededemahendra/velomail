import Testing
import AppKit
import Foundation
import VeloCore
@testable import VeloUI

/// The list had no sender disc at all. `SenderDisc` existed, but only as a
/// SwiftUI view used in the thread transcript -- the list is an `NSTableView`,
/// so the row could not use it and simply went without.
///
/// The wiring test at the bottom is the one that matters: this project's
/// recurring failure is a capability that exists, is tested, and is reachable
/// from nothing.
@MainActor
@Suite struct SenderDiscViewTests {
    private func thread(_ id: String = "t1", sender: String = "Cloudflare <noreply@cloudflare.com>") -> MailThread {
        MailThread(id: id, sender: sender, snippet: "snippet",
                   lastMessageDate: Date(timeIntervalSince1970: 0),
                   isUnread: false, hasAttachments: false, labelIDs: ["INBOX"])
    }

    /// Every text field in a view tree, in order.
    private func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField { found.append(field.stringValue) }
        for child in view.subviews { found.append(contentsOf: labels(in: child)) }
        return found
    }

    private func discs(in view: NSView) -> [SenderDiscView] {
        var found: [SenderDiscView] = []
        if let disc = view as? SenderDiscView { found.append(disc) }
        for child in view.subviews { found.append(contentsOf: discs(in: child)) }
        return found
    }

    @Test func theDiscShowsTheSendersInitial() {
        #expect(labels(in: SenderDiscView(name: "Cloudflare")).contains("C"))
        #expect(labels(in: SenderDiscView(name: "no-reply@asana.com")).contains("N"))
    }

    @Test func aSenderWithNoLetterAtAllStillGetsADisc() {
        // Rather than an empty circle, or a crash on `first`.
        #expect(labels(in: SenderDiscView(name: "<>")).contains("?"))
    }

    @Test func theSameSenderIsAlwaysTheSameColour() {
        let one = SenderDiscView(name: "Cloudflare").fill
        let again = SenderDiscView(name: "Cloudflare").fill
        #expect(one == again)
        #expect(SenderDiscView(name: "GitHub").fill != one)
    }

    /// The disc has to be keyed on the name the row is *showing*, not on the
    /// thread's sender. In Sent the row shows the recipient, and a disc drawn
    /// from the sender would put the reader's own initial beside every row.
    @Test func theDiscFollowsTheNameTheRowDisplays() {
        let sent = thread(sender: "me@x.com")
        let row = ThreadRowView(thread: sent, isMarked: false, name: "Peta Bilston",
                                dateText: "Today", previewLines: 1)

        #expect(labels(in: row).contains("P"))
        #expect(!labels(in: row).contains("M"))
    }

    @Test func everyRowCarriesExactlyOneDisc() {
        let row = ThreadRowView(thread: thread(), isMarked: false, name: "Cloudflare",
                                dateText: "Today", previewLines: 1)

        #expect(discs(in: row).count == 1)
        #expect(labels(in: row).contains("C"))
    }

    /// The name is already spoken; a letter read out beside it is noise.
    @Test func theDiscIsNotSpokenAloud() {
        let disc = SenderDiscView(name: "Cloudflare")
        #expect(disc.isAccessibilityElement() == false)
    }

    /// Both lines of a row must start at the same x.
    ///
    /// They did not. The multi-select tick and the unread dot sat inside the
    /// text block, ahead of the sender, so the name was indented past the
    /// snippet beneath it -- and by a different amount depending on whether the
    /// row was unread, because the dot is empty when it is not. Beside the new
    /// disc it read as a gap somebody forgot to close.
    private func field(_ text: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == text { return field }
        for child in view.subviews {
            if let found = field(text, in: child) { return found }
        }
        return nil
    }

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

    private func leading(of text: String, in row: ThreadRowView) -> CGFloat? {
        guard let field = field(text, in: row) else { return nil }
        return field.convert(field.bounds, to: row).minX
    }

    @Test func theSenderAndTheSnippetStartAtTheSameX() throws {
        for unread in [false, true] {
            let row = laidOutRow(unread: unread)
            let sender = try #require(leading(of: "Cloudflare", in: row))
            let snippet = try #require(leading(of: "the snippet", in: row))

            #expect(abs(sender - snippet) < 0.5,
                    "unread=\(unread): sender at \(sender), snippet at \(snippet)")
        }
    }

    /// And the indent must not depend on whether the row happens to be unread.
    @Test func theRowDoesNotShiftWhenItIsRead() throws {
        let unreadX = try #require(leading(of: "Cloudflare", in: laidOutRow(unread: true)))
        let readX = try #require(leading(of: "Cloudflare", in: laidOutRow(unread: false)))

        #expect(abs(unreadX - readX) < 0.5)
    }
}
