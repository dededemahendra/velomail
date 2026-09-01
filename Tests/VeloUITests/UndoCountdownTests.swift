import Testing
import AppKit
import SwiftUI
import Foundation
@testable import VeloUI

/// From a recording of a run of archives: the countdown bar sat at 100% for the
/// whole ten seconds. Sampled off the video, the lit part of the capsule was
/// identical at t = 5, 6, 7, 9, 11 and 13 seconds.
///
/// It was written as `ProgressView(timerInterval: Date()...deadline)`, with
/// `Date()` evaluated inside `body`. An interval is a value, so the timer
/// restarted every time the value did -- which is every time the body ran, and
/// archiving a run of threads redraws constantly. On an idle window it drained
/// correctly, which is why an earlier recording of a single archive looked fine.
///
/// The fraction is now computed from a window fixed when the offer opened, and
/// the arithmetic is a plain function that can be checked directly. The timer
/// form could not be: it draws nothing in an offscreen render, so a test that
/// measured its pixels reported the same 11 lit pixels whether nine seconds
/// remained or one.
@MainActor
@Suite struct UndoCountdownTests {
    private let opened = Date(timeIntervalSince1970: 1_000)
    private var window: ClosedRange<Date> { opened...opened.addingTimeInterval(10) }

    private func remaining(after seconds: TimeInterval) -> Double {
        UndoBanner.fractionRemaining(at: opened.addingTimeInterval(seconds), of: window)
    }

    @Test func afullWindowIsFullAndAnExpiredOneIsEmpty() {
        #expect(remaining(after: 0) == 1)
        #expect(remaining(after: 10) == 0)
    }

    @Test func itDrainsInProportionToTheTimeGone() {
        #expect(abs(remaining(after: 2.5) - 0.75) < 0.0001)
        #expect(abs(remaining(after: 5) - 0.5) < 0.0001)
        #expect(abs(remaining(after: 9) - 0.1) < 0.0001)
    }

    /// The reading depends only on the moment and the window, never on when it
    /// is asked. This is the property the old version did not have: the same
    /// instant read differently depending on how recently the view had redrawn.
    @Test func theSameMomentAlwaysReadsTheSame() {
        let readings = (0..<5).map { _ in remaining(after: 3) }
        #expect(Set(readings).count == 1)
    }

    /// A tick can land after the deadline before the banner is taken away.
    @Test func aTickAfterTheDeadlineReadsEmptyRatherThanNegative() {
        #expect(remaining(after: 30) == 0)
    }

    /// And one from before it opened cannot read past full.
    @Test func aTickBeforeTheWindowReadsFullRatherThanOverOne() {
        #expect(remaining(after: -5) == 1)
    }

    @Test func aWindowOfNoLengthDoesNotDivideByZero() {
        let instant = opened...opened
        #expect(UndoBanner.fractionRemaining(at: opened, of: instant) == 0)
    }

    // MARK: - What is actually drawn

    /// Lit pixels in a rendered banner with `remaining` seconds left.
    ///
    /// This is only possible because the bar is determinate now. The timer form
    /// drew nothing at all offscreen, so the same measurement returned 11 for
    /// nine seconds left and 11 for one -- the bug was invisible to it.
    private func litPixels(remaining: TimeInterval) -> Int {
        let end = Date().addingTimeInterval(remaining)
        let banner = UndoBanner(prompt: "Archived",
                                interval: end.addingTimeInterval(-10)...end, onUndo: {})
        let host = NSHostingView(rootView: banner.frame(width: 520))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 90)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData else { return -1 }

        let bytesPerRow = rep.bytesPerRow, samples = rep.samplesPerPixel
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let offset = y * bytesPerRow + x * samples
                if data[offset] > 150 && data[offset + 1] > 150 && data[offset + 2] > 150 {
                    count += 1
                }
            }
        }
        return count
    }

    @Test func theDrawnBarShrinksAsTheWindowRunsOut() {
        let nine = litPixels(remaining: 9)
        let five = litPixels(remaining: 5)
        let one = litPixels(remaining: 1)

        #expect(nine > five && five > one, "9s=\(nine) 5s=\(five) 1s=\(one)")
        // Roughly proportional, not merely ordered: a bar that jumped straight
        // to empty would satisfy the ordering above.
        #expect(Double(five) / Double(nine) > 0.35, "9s=\(nine) 5s=\(five)")
        #expect(Double(five) / Double(nine) < 0.75, "9s=\(nine) 5s=\(five)")
    }
}
