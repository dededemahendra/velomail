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
}
