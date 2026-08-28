import Testing
import SwiftUI
import AppKit
import Foundation
@testable import VeloUI

/// The disc is a fixed colour in both themes, on purpose: one correspondent
/// should be one colour whichever way the reader has their Mac set. That makes
/// it the one colour in the app no theme can rescue, so its contrast is checked
/// here rather than guessed at by eye.
@Suite struct SenderDiscContrastTests {
    /// WCAG relative luminance.
    private func luminance(_ colour: NSColor) -> Double {
        guard let rgb = colour.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent)
             + 0.7152 * channel(rgb.greenComponent)
             + 0.0722 * channel(rgb.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func disc(for sender: String) -> NSColor {
        NSColor(SenderDisc.fill(for: sender))
    }

    /// A spread of real-looking addresses, so this covers the whole hue wheel
    /// rather than whichever colour one example happens to land on.
    private let senders = [
        "Asana <no-reply@asana.com>", "Peta Bilston <peta@example.com>",
        "Natalie <natalie@sistercreatives.co>", "Xero <billing@xero.com>",
        "GitHub <notifications@github.com>", "a@x.com", "b@x.com", "c@x.com",
        "warren@livinglegacyforest.com", "salsa@sistercreatives.co",
        "hello@hubspot.com", "peta.bilston@wellingtondam.org.au",
    ]

    @Test func theInitialIsLegibleOnEveryDisc() {
        // It was 0.78 brightness first, which gave about two to one and looked
        // washed out. 3:1 is the WCAG floor for large or bold text, which a
        // 12pt semibold letter on a 26pt disc is.
        for sender in senders {
            let ratio = contrast(disc(for: sender), .white)
            #expect(ratio >= 3.0, "\(sender) reads at \(String(format: "%.2f", ratio)):1")
        }
    }

    @Test func theDiscIsVisibleAgainstALightWindow() {
        for sender in senders {
            let ratio = contrast(disc(for: sender), .white)
            #expect(ratio >= 3.0, "\(sender) disappears on white")
        }
    }

    @Test func theDiscIsVisibleAgainstADarkWindow() {
        // The reader runs the app in dark mode. A fixed colour cannot be
        // rescued by a theme, so it has to work on both grounds.
        let darkGround = NSColor(calibratedWhite: 0.12, alpha: 1)
        for sender in senders {
            let ratio = contrast(disc(for: sender), darkGround)
            #expect(ratio >= 2.0, "\(sender) disappears on dark: \(String(format: "%.2f", ratio)):1")
        }
    }

    @Test func noTwoOfTheseLandOnTheSameColour() {
        let hues = Set(senders.map { MessageAddressing.hue(for: $0) })
        #expect(hues.count == senders.count)
    }
}
