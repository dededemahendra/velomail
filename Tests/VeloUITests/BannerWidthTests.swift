import Testing
import AppKit
import SwiftUI
import Foundation
@testable import VeloUI

/// The banners are toasts, and a toast is read in one glance. Stretched across
/// a wide window the eye has to travel from an icon on the far left to a button
/// on the far right to learn that one thread was archived.
///
/// Each is an `HStack` with a `Spacer` in it, so it takes every point the
/// window offers: on a 1600pt window the strip ran the whole 1600.
///
/// Measured by rendering and looking at the pixels, not by asking for a fitting
/// size. `fittingSize` reports the *ideal* width, which for a short prompt is
/// small whether or not the banner stretches -- a first version of these tests
/// used it and passed with the bug fully present.
@MainActor
@Suite struct BannerWidthTests {
    private let canvas = CGFloat(1600)
    /// Generous: the cap plus both outer paddings and some slack. The point is
    /// that it is nothing like the width of the window.
    private let ceiling = CGFloat(600)

    /// How wide the banner actually draws, given far more room than it should
    /// take.
    private func drawnWidth<V: View>(of banner: V) -> CGFloat? {
        let host = NSHostingView(rootView: banner)
        host.frame = NSRect(x: 0, y: 0, width: canvas, height: 140)
        // Without an appearance every dynamic system colour resolves invisible
        // and the whole thing measures as blank.
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData else { return nil }

        let bytesPerRow = rep.bytesPerRow, samples = rep.samplesPerPixel
        var minX = Int.max, maxX = Int.min
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let alpha = data[y * bytesPerRow + x * samples + (samples - 1)]
                guard alpha > 24 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
            }
        }
        guard maxX >= minX else { return nil }
        // Back to points; the rep is at backing scale.
        let scale = CGFloat(rep.pixelsWide) / canvas
        return CGFloat(maxX - minX + 1) / scale
    }

    private func expectCapped<V: View>(_ banner: V, _ what: String,
                                       sourceLocation: SourceLocation = #_sourceLocation) {
        guard let width = drawnWidth(of: banner) else {
            Issue.record("\(what) drew nothing at all", sourceLocation: sourceLocation)
            return
        }
        #expect(width <= ceiling, "\(what) drew \(width)pt wide in a \(canvas)pt window",
                sourceLocation: sourceLocation)
    }

    @Test func theUndoBannerDoesNotRunTheWidthOfTheWindow() {
        expectCapped(UndoBanner(prompt: "Archived", deadline: nil, onUndo: {}), "undo")
    }

    @Test func theNoticeBannerDoesNotRunTheWidthOfTheWindow() {
        expectCapped(NoticeBanner(text: "Marked all read"), "notice")
    }

    @Test func theFailureBannerDoesNotRunTheWidthOfTheWindow() {
        expectCapped(FailureBanner(prompt: "Could not send \u{201C}Lunch\u{201D}",
                                   canReopen: true, overflow: 2,
                                   onReopen: {}, onDismiss: {}), "failure")
    }

    @Test func theSignInBannerDoesNotRunTheWidthOfTheWindow() {
        expectCapped(SignInAgainBanner(onSignIn: {}), "sign-in")
    }

    /// A long prompt must not defeat the cap either -- the failure banner
    /// carries a subject, and subjects are arbitrary.
    @Test func aVeryLongPromptIsStillCapped() {
        expectCapped(FailureBanner(prompt: String(repeating: "a very long subject ", count: 12),
                                   canReopen: true, overflow: 0,
                                   onReopen: {}, onDismiss: {}), "long failure")
    }
}
