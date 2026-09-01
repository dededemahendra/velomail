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
    /// This is what caught the gradient clipping its own artwork: with no
    /// extension options a `CGGradient` paints nothing beyond its start point,
    /// so the corner of the mark that lay before the axis start came out
    /// unpainted -- a hard straight cut across the top-left arm, perpendicular
    /// to the gradient, that read as a design choice rather than a bug.
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


    /// Every pixel of the mark must actually receive colour.
    ///
    /// Measured against the mark's own outline rather than against a symmetry
    /// property, so it catches the gradient failing to reach *any* part of the
    /// artwork rather than only a part that happens to break the symmetry. The
    /// symmetry test above is blind to a shortfall at the far end of the axis;
    /// this is not.
    @Test func theGradientReachesEveryPartOfTheMark() throws {
        let representation = try #require(iconNamed("icon_512x512.png"))
        let design = AppIconRenderer.design(forPointSize: representation.pointSize)
        let path = try #require(AppIconRenderer.markPath(for: design))

        // The mark's own area, drawn flat, at the same scale the icon uses.
        let side = representation.pixels
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let scratch = try #require(CGContext(data: nil, width: side, height: side,
                                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        scratch.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
        scratch.addPath(path)
        scratch.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        scratch.fillPath()
        let outline = try #require(scratch.makeImage())

        let expected = pixels(of: outline).count { $0 & 0xFF > 0x80 }
        let painted = pixels(of: AppIconRenderer.image(representation)).count(where: isLit)

        #expect(expected > 10_000, "the mark outline is suspiciously small: \(expected)")
        let shortfall = Double(expected - painted) / Double(expected)
        // Threshold set from measurement, not taste: correct comes out at
        // -0.46% (the lit test is marginally more generous than the outline's
        // alpha cut, so painted slightly exceeds it), and dropping the gradient
        // extensions gives +1.19%. 0.5% sits between them with room either way.
        #expect(shortfall < 0.005,
                "the gradient left \(expected - painted) of \(expected) mark pixels unpainted")
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
}
