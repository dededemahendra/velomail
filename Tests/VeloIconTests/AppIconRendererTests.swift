import Testing
import CoreGraphics
import Foundation
@testable import VeloIcon

/// A `.icns` is assembled from a fixed set of named PNGs, and `iconutil` is
/// unforgiving: one missing file, or one file whose pixel dimensions do not
/// match the name it was given, and macOS quietly falls back to the blank page
/// icon rather than reporting anything. That failure is invisible until someone
/// looks at the Dock, so it is worth a test.
@Suite struct AppIconRendererTests {
    @Test func everyRepresentationMacOSAsksForIsProduced() {
        let named = Set(AppIconRenderer.representations.map(\.filename))

        #expect(named == [
            "icon_16x16.png", "icon_16x16@2x.png",
            "icon_32x32.png", "icon_32x32@2x.png",
            "icon_128x128.png", "icon_128x128@2x.png",
            "icon_256x256.png", "icon_256x256@2x.png",
            "icon_512x512.png", "icon_512x512@2x.png",
        ])
    }

    @Test func eachRepresentationIsRenderedAtExactlyThePixelSizeItsNameClaims() {
        for representation in AppIconRenderer.representations {
            let image = AppIconRenderer.image(representation)
            #expect(image.width == representation.pixels,
                    "\(representation.filename) should be \(representation.pixels)px wide")
            #expect(image.height == representation.pixels,
                    "\(representation.filename) should be \(representation.pixels)px tall")
        }
    }

    /// `icon_16x16@2x` and `icon_32x32` are both 32 pixels, and it is tempting
    /// to treat them as the same picture. They are not: the first is the 16pt
    /// design at double resolution, the second is the 32pt design. At 16pt the
    /// two chevrons close up into a single blob, so that size shows one.
    @Test func theSixteenPointDesignIsSimplerThanTheThirtyTwoPointOne() {
        let small = AppIconRenderer.design(forPointSize: 16)
        let large = AppIconRenderer.design(forPointSize: 32)
        let full = AppIconRenderer.design(forPointSize: 512)

        #expect(small.chevrons == 1)
        #expect(large.chevrons == 2)
        #expect(full.chevrons == 2)
        // Small sizes need a proportionally heavier line to survive rounding
        // to whole pixels.
        #expect(small.strokeScale > full.strokeScale)
        #expect(large.strokeScale > full.strokeScale)
    }

    /// The mark is a pair of chevrons, and a chevron that meets at a sharp
    /// point is not what was asked for. Rounding the apex is the difference
    /// between the mark and a plain "greater than" sign, so it is worth
    /// pinning: a mitred corner would put pixels in the exact apex, a rounded
    /// one leaves that corner clipped back.
    @Test func theChevronApexIsRoundedRatherThanPointed() {
        let radius = AppIconRenderer.apexRadius
        #expect(radius > 0)

        let pointed = AppIconRenderer.chevronPath(apexX: 500, apexRadius: 0)
        let rounded = AppIconRenderer.chevronPath(apexX: 500, apexRadius: radius)
        // A rounded corner cuts the apex back, so the path stops short of the
        // x a mitred one would reach.
        #expect(rounded.boundingBoxOfPath.maxX < pointed.boundingBoxOfPath.maxX)
    }

    /// The two 32-pixel files must actually differ. Keyed on pixel size rather
    /// than point size they would come out identical, and the simplification
    /// above would be decorative rather than real.
    @Test func theTwoThirtyTwoPixelFilesAreDifferentPictures() throws {
        let sixteenAtTwice = AppIconRenderer.representations.first { $0.filename == "icon_16x16@2x.png" }
        let thirtyTwo = AppIconRenderer.representations.first { $0.filename == "icon_32x32.png" }
        let a = try #require(sixteenAtTwice)
        let b = try #require(thirtyTwo)
        #expect(a.pixels == 32 && b.pixels == 32)

        #expect(pixels(of: AppIconRenderer.image(a)) != pixels(of: AppIconRenderer.image(b)))
    }

    @Test func writingAnIconsetLeavesEveryFileOnDisk() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-icon-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: directory) }

        try AppIconRenderer.writeIconset(to: directory)

        for representation in AppIconRenderer.representations {
            let file = directory.appendingPathComponent(representation.filename)
            #expect(FileManager.default.fileExists(atPath: file.path),
                    "missing \(representation.filename)")
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
            #expect((size ?? 0) > 0, "\(representation.filename) is empty")
        }
    }

    /// Each chevron is symmetric about the tile's centre line, so the mark
    /// must paint the same area above it as below.
    ///
    /// This is how the gradient clipping its own artwork was first caught, back
    /// when the mark ran to 68% of the tile and its top-left corner fell outside
    /// the gradient's axis. At 58% it no longer does, so this no longer detects
    /// that particular bug -- `theMarkGradientPaintsEveryPixelItIsGivenEvenOutsideItsAxis`
    /// took that job, and does it whatever size the mark is. What remains here
    /// is still worth asserting: a geometry change that made the mark lopsided
    /// would show up nowhere else.
    @Test func theMarkIsPaintedSymmetricallyAboutTheCentreLine() throws {
        let representation = try #require(iconNamed("icon_512x512.png"))
        let image = AppIconRenderer.image(representation)
        let raw = pixels(of: image)
        let side = image.width

        var top = 0, bottom = 0
        for y in 0..<side {
            for x in 0..<side where isLit(raw[y * side + x]) {
                if y < side / 2 { top += 1 } else { bottom += 1 }
            }
        }

        #expect(top > 1000 && bottom > 1000, "mark barely drawn: top \(top), bottom \(bottom)")
        let difference = Double(abs(top - bottom)) / Double(max(top, bottom))
        #expect(difference < 0.01,
                "mark is lopsided: \(top) lit above the centre line, \(bottom) below")
    }

    /// The icon must not be a blank square. Counts distinct colours; a ground
    /// gradient plus a gradient-stroked mark is many, an empty canvas is one.
    @Test func theIconActuallyHasAMarkOnIt() throws {
        let image = AppIconRenderer.image(try #require(iconNamed("icon_512x512.png")))
        let colours = Set(pixels(of: image))
        #expect(colours.count > 500, "only \(colours.count) distinct colours -- is anything drawn?")
    }


    /// The mark's gradient must paint every pixel it is given, including any
    /// that fall outside the gradient's own axis.
    ///
    /// Handed an oversized path on purpose. The shipped mark sits well inside
    /// the axis, so the icon's own pixels can no longer tell whether the
    /// extension options are set -- a coverage test against the real artwork
    /// passes either way and guards nothing. This one fails the moment either
    /// option is dropped, whatever size the mark happens to be.
    @Test func theMarkGradientPaintsEveryPixelItIsGivenEvenOutsideItsAxis() throws {
        let side = 512
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: nil, width: side, height: side,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)

        // The whole canvas: its corners lie well before the gradient's start
        // and well past its end.
        AppIconRenderer.fillWithMarkGradient(
            CGPath(rect: CGRect(x: 0, y: 0, width: 1024, height: 1024), transform: nil),
            in: context)

        let raw = pixels(of: try #require(context.makeImage()))
        let unpainted = raw.count { ($0 >> 24) & 0xFF < 0xFF }
        #expect(unpainted == 0, "\(unpainted) of \(raw.count) pixels left unpainted")
    }

    /// Clearly not the charcoal ground: the mark is the only saturated thing
    /// on the tile.
    private func isLit(_ p: UInt32) -> Bool {
        let r = p & 0xFF, g = (p >> 8) & 0xFF, b = (p >> 16) & 0xFF
        return max(r, max(g, b)) > 0x60 && (max(r, max(g, b)) - min(r, min(g, b))) > 0x28
    }

    /// Named lookup. Selecting by pixel count is ambiguous: `icon_256x256@2x`
    /// and `icon_512x512` are both 512 pixels, and `first(where:)` silently
    /// returns the former.
    private func iconNamed(_ name: String) -> AppIconRenderer.Representation? {
        AppIconRenderer.representations.first { $0.filename == name }
    }

    private func pixels(of image: CGImage) -> [UInt32] {
        let width = image.width, height = image.height
        var buffer = [UInt32](repeating: 0, count: width * height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }

    // MARK: - The layered mark

    /// macOS 26 draws the tile itself, per appearance, and composites the app's
    /// layers on top. That is how an icon comes to have a light and a dark
    /// form at all: the artwork supplies the mark, the system supplies the
    /// ground. A flat picture of a dark tile -- which is what the `.icns` is --
    /// hides the ground and looks the same in both.
    ///
    /// So the layer has to be the chevrons alone, on nothing.
    @Test func theLayerIsTheMarkAloneOnTransparency() throws {
        let image = AppIconRenderer.markLayer(pixels: 512)
        #expect(image.width == 512)

        let pixels = pixels(of: image)
        let side = image.width
        func alpha(_ x: Int, _ y: Int) -> UInt32 { (pixels[y * side + x] >> 24) & 0xFF }

        // The corners are where a tile would be, and there must not be one.
        for (x, y) in [(4, 4), (side - 5, 4), (4, side - 5), (side - 5, side - 5)] {
            #expect(alpha(x, y) == 0, "something is drawn at \(x),\(y) -- a tile would be")
        }
        // And the mark itself is there.
        #expect(pixels.count { ($0 >> 24) & 0xFF > 0x80 } > 10_000)
    }

    /// The mark sits on a near-white tile in light mode and a dark one in dark
    /// mode, so its colours have to carry against both. The first pair --
    /// pale pink to pale cyan, chosen against charcoal -- vanished on white.
    @Test func theMarkIsDarkEnoughToReadOnALightTile() {
        let image = AppIconRenderer.markLayer(pixels: 256)
        let lit = pixels(of: image).filter { ($0 >> 24) & 0xFF > 0xC0 }
        #expect(!lit.isEmpty)

        // Relative luminance of every solid pixel of the mark, against white.
        let luminances = lit.map { pixel -> Double in
            let r = Double(pixel & 0xFF), g = Double((pixel >> 8) & 0xFF), b = Double((pixel >> 16) & 0xFF)
            return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        let brightest = luminances.max() ?? 1
        #expect(brightest < 0.62,
                "the palest part of the mark is \(brightest) against a 0.95 tile")
    }
}
