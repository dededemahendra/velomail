import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the Velo Mail app icon: a pair of rounded chevrons on a dark tile.
///
/// The chevron is the app's own mark -- the guillemet a row already carries for
/// mail addressed to you and nobody else -- so the icon says something the app
/// says rather than borrowing a generic envelope.
///
/// Build-time tooling, deliberately outside the app's dependency graph: none of
/// this ships in `VeloMail`. Drawn in code rather than checked in as a `.icns`
/// so the icon is diffable and editable by changing numbers, which is how every
/// other asset in this repo works -- there are no binary assets.
public enum AppIconRenderer {

    // MARK: - What macOS asks for

    /// One file in the `.iconset`.
    ///
    /// Point size and scale are kept separate rather than collapsed into a
    /// pixel count, because they are not the same question. `icon_16x16@2x` and
    /// `icon_32x32` are both 32 pixels but are *different pictures*: the first
    /// is the 16pt design at double resolution, the second is the 32pt design.
    public struct Representation: Sendable, Hashable {
        public let pointSize: Int
        public let scale: Int

        public var pixels: Int { pointSize * scale }
        public var filename: String {
            "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        }
    }

    public static let representations: [Representation] = [16, 32, 128, 256, 512]
        .flatMap { point in [1, 2].map { Representation(pointSize: point, scale: $0) } }

    // MARK: - How much detail a size can carry

    /// What to draw at a given point size.
    ///
    /// Small sizes get their own artwork rather than a scaled-down copy. The
    /// reference this icon's treatment came from does not do this, and at 16pt
    /// its mark collapses into an illegible ring.
    public struct Design: Sendable, Equatable {
        /// How many chevrons to draw. Two is the mark; at 16pt the gap between
        /// them falls under a pixel and the pair closes into a blob, so that
        /// size shows one.
        public let chevrons: Int
        /// Stroke weight relative to the mark, before scaling. Small sizes need
        /// a proportionally heavier line to survive rounding to whole pixels.
        public let strokeScale: CGFloat
    }

    public static func design(forPointSize pointSize: Int) -> Design {
        switch pointSize {
        case ..<32: return Design(chevrons: 1, strokeScale: 1.30)
        case 32..<128: return Design(chevrons: 2, strokeScale: 1.15)
        default: return Design(chevrons: 2, strokeScale: 1.0)
        }
    }

    // MARK: - Geometry

    /// How much the apex is cut back. A chevron meeting at a sharp point reads
    /// as a "greater than" sign; rounding it is what makes it a mark.
    public static let apexRadius: CGFloat = 88

    /// One chevron: two arms meeting at the right, corner rounded.
    ///
    /// `addArc(tangent1End:tangent2End:radius:)` replaces the corner with an arc
    /// tangent to both arms, which is why the path stops short of `apexX` -- the
    /// sharper the angle, the further back it cuts.
    public static func chevronPath(apexX: CGFloat, apexRadius: CGFloat) -> CGPath {
        let armX: CGFloat = 200, armY: CGFloat = 250
        let path = CGMutablePath()
        path.move(to: CGPoint(x: apexX - armX, y: 512 + armY))
        if apexRadius > 0 {
            path.addArc(tangent1End: CGPoint(x: apexX, y: 512),
                        tangent2End: CGPoint(x: apexX - armX, y: 512 - armY),
                        radius: apexRadius)
        } else {
            path.addLine(to: CGPoint(x: apexX, y: 512))
        }
        path.addLine(to: CGPoint(x: apexX - armX, y: 512 - armY))
        return path
    }

    // MARK: - Palette

    /// Charcoal, not black: a pure black icon loses its silhouette against a
    /// dark Dock, and the ground needs to read as a lit surface.
    private static let groundTop = rgb(0x2E, 0x2E, 0x30)
    private static let groundBottom = rgb(0x12, 0x12, 0x14)

    /// The mark's gradient, running top-left to bottom-right.
    private static let markStops = [rgb(0xFF, 0xA0, 0xF0), rgb(0x8F, 0xA8, 0xFF), rgb(0x22, 0xE6, 0xFF)]

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: 1)
    }

    // MARK: - Drawing

    public static func image(_ representation: Representation) -> CGImage {
        let side = representation.pixels
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)

        // Everything below is written against a 1024 canvas and scaled once, so
        // the numbers stay readable and every size stays in proportion.
        let unit = CGFloat(side) / 1024
        context.scaleBy(x: unit, y: unit)

        draw(in: context, design: design(forPointSize: representation.pointSize))
        return context.makeImage()!
    }

    private static func draw(in context: CGContext, design: Design) {
        let squircle = CGRect(x: 100, y: 100, width: 824, height: 824)
        // 27% of the side. Big Sur nominally rounds at 22.5%, but against the
        // reference that read visibly square, and mail apps sit next to it.
        let shape = CGPath(roundedRect: squircle, cornerWidth: 222, cornerHeight: 222,
                           transform: nil)

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let ground = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                colors: [groundTop, groundBottom] as CFArray,
                                locations: [0, 1])!
        // Top to bottom: CoreGraphics origin is bottom-left, so the light end
        // goes at maxY.
        context.drawLinearGradient(ground,
                                   start: CGPoint(x: 512, y: squircle.maxY),
                                   end: CGPoint(x: 512, y: squircle.minY),
                                   options: [])
        context.restoreGState()

        // A faint rim so the tile reads as a physical surface catching light
        // rather than a flat swatch.
        context.saveGState()
        context.addPath(shape)
        context.setLineWidth(3)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
        context.strokePath()
        context.restoreGState()

        drawMark(in: context, design: design)
    }

    /// The chevrons, gradient-filled by clipping to the artwork and painting one
    /// gradient across the whole mark -- so the ramp runs continuously from the
    /// first chevron through the second rather than restarting on each.
    private static func drawMark(in context: CGContext, design: Design) {
        let mark = CGMutablePath()
        let width = 96 * design.strokeScale
        // At 16pt the survivor is the leading chevron, so what remains is the
        // front of the mark rather than an arbitrary half of it.
        let apexes: [CGFloat] = design.chevrons == 1 ? [740] : [470, 740]
        for apexX in apexes {
            mark.addPath(stroked(chevronPath(apexX: apexX, apexRadius: apexRadius),
                                 width: width, context: context))
        }

        // Centred and sized by its own bounds rather than by fixed coordinates,
        // so dropping a chevron at 16pt does not leave the survivor sitting off
        // to one side, and both designs carry the same weight on the tile.
        var placement = centring(mark.boundingBoxOfPath, longestSide: 560)
        guard let placed = mark.copy(using: &placement) else { return }

        context.saveGState()
        context.addPath(placed)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: markStops as CFArray, locations: [0, 0.55, 1])!
        // Fixed to the tile, not the mark, so the ramp reads the same way at
        // every size regardless of how much of it the artwork covers.
        //
        // Both extension options are required, not optional polish: without
        // them a CGGradient paints nothing outside its own axis, and the corner
        // of the mark lying before the start point came out unpainted -- a hard
        // straight cut across the top-left arm, square against three rounded
        // ones. The ends clamp to the first and last stop, which is what the
        // extremes of the mark should be anyway.
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 300, y: 764),
                                   end: CGPoint(x: 790, y: 262),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// Scales `bounds` so its longest side is `longestSide`, then centres it on
    /// the tile.
    private static func centring(_ bounds: CGRect, longestSide: CGFloat) -> CGAffineTransform {
        guard bounds.width > 0, bounds.height > 0 else { return .identity }
        let scale = longestSide / max(bounds.width, bounds.height)
        return CGAffineTransform(translationX: 512, y: 512)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
    }

    /// Turns a line into the outline of that line, so it can be clipped and
    /// filled with a gradient. Round caps and joins throughout: the mark is a
    /// rounded chevron, and a butt cap would put a hard corner on every arm end.
    /// `replacePathWithStrokedPath` works on the context's current path, which
    /// is why this borrows it and puts it back.
    private static func stroked(_ path: CGPath, width: CGFloat, context: CGContext) -> CGPath {
        context.saveGState()
        context.beginPath()
        context.addPath(path)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.replacePathWithStrokedPath()
        let result = context.path?.copy() ?? CGMutablePath()
        context.beginPath()
        context.restoreGState()
        return result
    }

    // MARK: - Output

    public static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for representation in representations {
            let url = directory.appendingPathComponent(representation.filename)
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw IconError.couldNotWrite(representation.filename)
            }
            CGImageDestinationAddImage(destination, image(representation), nil)
            guard CGImageDestinationFinalize(destination) else {
                throw IconError.couldNotWrite(representation.filename)
            }
        }
    }

    public enum IconError: Error, CustomStringConvertible {
        case couldNotWrite(String)
        public var description: String {
            switch self {
            case let .couldNotWrite(name): return "could not write \(name)"
            }
        }
    }
}
