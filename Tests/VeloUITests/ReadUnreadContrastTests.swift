import Testing
import AppKit
import Foundation
import VeloCore
@testable import VeloUI

/// Read and unread have to be tellable apart at a glance, across the whole row.
///
/// They were separated by a dot and the sender's weight, and nothing else: the
/// snippet -- the widest text on the row -- was drawn at one weight either way,
/// and every row shared one background. Rendered and measured, the mean
/// difference between a read row and an unread one was 0.022 on a 0...1 scale.
/// Gmail's strongest cue is the row itself, and that is the one this list did
/// not have.
@MainActor
@Suite struct ReadUnreadContrastTests {
    private func thread(_ unread: Bool) -> MailThread {
        MailThread(id: "t", sender: "Better Stack Weekly",
                   snippet: "No downtime this week - Gede, you had no incidents at all",
                   lastMessageDate: Date(), isUnread: unread, hasAttachments: false,
                   labelIDs: unread ? ["UNREAD", "INBOX"] : ["INBOX"],
                   messageCount: 1, recipientCount: 3)
    }

    private func row(_ unread: Bool) -> ThreadRowView {
        let row = ThreadRowView()
        row.frame = NSRect(x: 0, y: 0, width: 760, height: 44)
        row.appearance = NSAppearance(named: .darkAqua)
        row.configure(thread: thread(unread), isMarked: false, name: "Better Stack Weekly",
                      dateText: "3:29 PM", previewLines: 1)
        row.layoutSubtreeIfNeeded()
        return row
    }

    /// The row as the table composes it: the ground the table wraps around the
    /// cell view, over an opaque backdrop.
    ///
    /// The backdrop is not decoration. The ground paints a *scrim* -- black at
    /// low alpha -- and a scrim over nothing is still nothing: rendered without
    /// something behind it, read and unread rows both come out at zero and the
    /// measurement says they match when they plainly do not.
    private func composedRow(_ unread: Bool, selected: Bool = false) -> NSView {
        let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 44))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        backdrop.appearance = NSAppearance(named: .darkAqua)

        let ground = ThreadRowBackground()
        ground.frame = backdrop.bounds
        ground.isUnread = unread
        ground.isSelected = selected
        ground.addSubview(row(unread))
        backdrop.addSubview(ground)
        backdrop.layoutSubtreeIfNeeded()
        return backdrop
    }

    /// Mean luminance of a rendered view, 0...1.
    private func brightness(of view: NSView) -> Double {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData else { return -1 }
        var total = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let p = y * rep.bytesPerRow + x * rep.samplesPerPixel
                total += (Double(data[p]) + Double(data[p + 1]) + Double(data[p + 2])) / 3 / 255
            }
        }
        return total / Double(rep.pixelsHigh * rep.pixelsWide)
    }

    private func weight(of font: NSFont) -> Double {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? Double ?? 0
    }

    /// The snippet is the widest text on the row and the thing the eye lands on
    /// when deciding whether to open something. It was the same weight either
    /// way.
    @Test func theSnippetIsHeavierWhenTheMailIsUnread() {
        #expect(weight(of: row(true).snippetFont) > weight(of: row(false).snippetFont))
    }

    /// Rendered, not reasoned about: the fonts could differ and still look the
    /// same. 0.033 is half again the 0.022 the row managed before, which is the
    /// difference the reader called too slight to see.
    @Test func theWholeRowReadsDifferently() {
        let delta = brightness(of: composedRow(true)) - brightness(of: composedRow(false))
        #expect(delta > 0.033, "unread and read rows differ by only \(delta)")
    }

    /// The ground on its own, with no text over it -- the text legitimately
    /// differs between read and unread, and it would drown out the thing being
    /// measured here.
    private func ground(_ unread: Bool, selected: Bool = false) -> NSView {
        let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 44))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        backdrop.appearance = NSAppearance(named: .darkAqua)
        let ground = ThreadRowBackground()
        ground.frame = backdrop.bounds
        ground.isUnread = unread
        ground.isSelected = selected
        backdrop.addSubview(ground)
        backdrop.layoutSubtreeIfNeeded()
        return backdrop
    }

    /// The row's own ground, which is the cue Gmail leans on hardest and this
    /// list had none of.
    @Test func readMailSitsOnADarkerGround() {
        #expect(brightness(of: ground(false)) < brightness(of: ground(true)))
    }

    /// Selection already answers "which row is this". A scrim underneath it
    /// would only muddy the highlight, so a selected read row is drawn like any
    /// other selected row.
    @Test func selectionSuppressesTheScrim() {
        #expect(brightness(of: ground(false, selected: true))
                == brightness(of: ground(true, selected: true)),
                "the scrim is still being drawn under the selection")
    }

    /// A scrim is only visible against something. Without this the two
    /// measurements above would both be zero and would agree for the wrong
    /// reason.
    @Test func theBackdropIsWhatMakesTheScrimMeasurable() {
        #expect(brightness(of: composedRow(true)) > 0.05)
    }
}
