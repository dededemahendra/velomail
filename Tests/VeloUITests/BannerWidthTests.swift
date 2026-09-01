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
        expectCapped(UndoBanner(prompt: "Archived", interval: nil, onUndo: {}), "undo")
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

    // MARK: - Contrast

    /// Mean luminance of a horizontal band through the middle of the banner,
    /// rendered over `backdrop`.
    private func interiorLuminance<V: View>(of banner: V, over backdrop: Color) -> Double? {
        let host = NSHostingView(rootView: ZStack { backdrop; banner }.frame(width: 700, height: 120))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 120)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData else { return nil }

        // A band across the banner's own row, inset from its ends so the
        // sampling never strays onto the backdrop beside it.
        let bytesPerRow = rep.bytesPerRow, samples = rep.samplesPerPixel
        let scale = rep.pixelsWide / 700
        var total = 0.0, count = 0
        for y in (44 * scale)..<(64 * scale) {
            for x in (300 * scale)..<(400 * scale) {
                let offset = y * bytesPerRow + x * samples
                let r = Double(data[offset]), g = Double(data[offset + 1]), b = Double(data[offset + 2])
                total += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : nil
    }

    /// The banner floats over both the dark list and a white message body, and
    /// straddles the boundary between them. As a plain material it sampled
    /// whatever was behind it: the very same toast came out dark on its left
    /// half and near-white on its right, with "Undo" on a ground barely
    /// distinguishable from its own white text.
    @Test func theBannerLooksTheSameWhateverIsBehindIt() throws {
        let banner = UndoBanner(prompt: "Archived", interval: nil, onUndo: {})
        let onDark = try #require(interiorLuminance(of: banner, over: .black))
        let onLight = try #require(interiorLuminance(of: banner, over: .white))

        #expect(abs(onDark - onLight) < 0.12,
                "banner reads \(onDark) on a dark backdrop and \(onLight) on a light one")
    }

    /// And it has to stay dark enough for white text to sit on.
    @Test func theBannerStaysDarkOverAWhiteMessageBody() throws {
        let banner = UndoBanner(prompt: "Archived", interval: nil, onUndo: {})
        let onLight = try #require(interiorLuminance(of: banner, over: .white))

        #expect(onLight < 0.45, "banner interior is \(onLight) over white -- white text on it")
    }
}
