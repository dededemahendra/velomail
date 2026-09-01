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

    /// The mark's longest dimension, on the 1024 canvas.
    ///
    /// 58% of the 824 tile. It started at 560 -- 68% -- which crowded the
    /// corners: the mark ran nearly edge to edge and the tile stopped reading
    /// as a tile with something on it.
    public static let markSide: CGFloat = 480

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
    ///
    /// Deeper than the pale pink-to-cyan it started as. That pair was chosen
    /// against charcoal and was the right choice while the artwork carried its
    /// own dark tile. Now macOS draws the tile -- near-white in light mode --
    /// and those colours disappeared on it. These carry against both grounds.
    private static let markStops = [rgb(0xD9, 0x46, 0xEF), rgb(0x7C, 0x5C, 0xF5), rgb(0x22, 0x99, 0xDD)]

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
        guard let placed = markPath(for: design) else { return }
        fillWithMarkGradient(placed, in: context)
    }

    /// Fills `path` with the mark's gradient.
    ///
    /// Separated so it can be tested against a path larger than the gradient's
    /// axis. The mark currently sits well inside that axis, which means the
    /// icon's own pixels can no longer tell whether the extension options below
    /// are present -- so testing this at today's geometry proves nothing, and
    /// the test hands it something oversized instead.
    public static func fillWithMarkGradient(_ path: CGPath, in context: CGContext) {
        context.addPath(path)
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
        //
        // Only `drawsBeforeStartLocation` changes anything as the mark is
        // currently laid out -- nothing reaches past the axis end. The other is
        // kept because that is a fact about today's geometry, not a property
        // anyone moving a chevron would think to re-check.
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 300, y: 764),
                                   end: CGPoint(x: 790, y: 262),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// The mark's outline, placed on the tile, before any colour is put in it.
    ///
    /// Separated from the drawing so a test can measure how much of it the
    /// gradient actually reaches. That is not a hypothetical: a `CGGradient`
    /// paints nothing outside its own axis unless told to, and the first
    /// version of this left a corner of the mark unpainted.
    public static func markPath(for design: Design) -> CGPath? {
        // A scratch context purely to borrow `replacePathWithStrokedPath`,
        // which is a context operation rather than a path one.
        guard let scratch = CGContext(data: nil, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let mark = CGMutablePath()
        let width = 96 * design.strokeScale
        // At 16pt the survivor is the leading chevron, so what remains is the
        // front of the mark rather than an arbitrary half of it.
        let apexes: [CGFloat] = design.chevrons == 1 ? [740] : [470, 740]
        for apexX in apexes {
            mark.addPath(stroked(chevronPath(apexX: apexX, apexRadius: apexRadius),
                                 width: width, context: scratch))
        }

        // Centred and sized by its own bounds rather than by fixed coordinates,
        // so dropping a chevron at 16pt does not leave the survivor sitting off
        // to one side, and both designs carry the same weight on the tile.
        var placement = centring(mark.boundingBoxOfPath, longestSide: markSide)
        return mark.copy(using: &placement)
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

    /// The mark alone, on transparency, for the layered `.icon`.
    ///
    /// macOS 26 draws the tile itself, once per appearance, and composites the
    /// app's layers over it -- which is the whole mechanism by which an icon
    /// has a light and a dark form. Handing it a flat picture of a dark tile,
    /// which is what the `.icns` is, hides the ground and looks identical in
    /// both.
    public static func markLayer(pixels side: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setAllowsAntialiasing(true)
        let unit = CGFloat(side) / 1024
        context.scaleBy(x: unit, y: unit)

        // The full design: a layered icon is only ever drawn large, and the
        // system does its own scaling.
        guard let mark = markPath(for: design(forPointSize: 512)) else { return context.makeImage()! }
        fillWithMarkGradient(mark, in: context)
        return context.makeImage()!
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

    /// Writes an Icon Composer `.icon` bundle for `actool` to compile.
    ///
    /// Hand-written rather than produced by Icon Composer, which is a GUI. The
    /// shape was established by compiling candidates and reading the result
    /// back with `assetutil`: the `fill` belongs to a *group*, not to the
    /// document -- at the top level it compiles without complaint and is
    /// silently ignored, which is how a near-white ground came out charcoal.
    public static func writeIconBundle(to directory: URL, named name: String = "AppIcon") throws {
        let bundle = directory.appendingPathComponent("\(name).icon")
        let assets = bundle.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let markURL = assets.appendingPathComponent("mark.png")
        guard let destination = CGImageDestinationCreateWithURL(
            markURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw IconError.couldNotWrite("mark.png")
        }
        CGImageDestinationAddImage(destination, markLayer(pixels: 1024), nil)
        guard CGImageDestinationFinalize(destination) else {
            throw IconError.couldNotWrite("mark.png")
        }

        // The near-white is the *light* ground; the system derives the dark one
        // from it, which is what gives the icon its two appearances. A charcoal
        // fill here would produce two identical dark icons.
        let manifest = """
        {
          "groups" : [
            {
              "fill" : { "automatic-gradient" : "extended-srgb:0.96,0.96,0.98,1.00" },
              "layers" : [ { "image-name" : "mark.png", "name" : "Chevrons" } ]
            }
          ],
          "supported-platforms" : { "circles" : [], "squares" : [ "macOS" ] },
          "version" : 1
        }
        """
        try manifest.write(to: bundle.appendingPathComponent("icon.json"),
                           atomically: true, encoding: .utf8)
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
