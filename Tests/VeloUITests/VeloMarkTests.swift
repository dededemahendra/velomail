import Testing
import SwiftUI
import CoreGraphics
@testable import VeloUI
@testable import VeloIcon

/// The sign-in and setup screens draw the app's mark, and the icon is built
/// from its own copy of the same geometry -- the app does not link `VeloIcon`,
/// which exists to run `actool` and would drag the whole icon pipeline into the
/// shipped binary.
///
/// Two copies of a shape is a thing that drifts. This holds them together.
@Suite struct VeloMarkTests {
    @Test func theDrawnMarkMatchesTheIconsGeometry() {
        #expect(VeloMark.apexRadius == AppIconRenderer.apexRadius)

        // The same chevron, from each side, laid out on the icon's canvas.
        for apexX in VeloMark.apexes {
            let fromIcon = AppIconRenderer.chevronPath(apexX: apexX,
                                                       apexRadius: AppIconRenderer.apexRadius)
            var drawn = Path()
            drawn.move(to: CGPoint(x: apexX - VeloMark.armX, y: 512 + VeloMark.armY))
            drawn.addArc(tangent1End: CGPoint(x: apexX, y: 512),
                         tangent2End: CGPoint(x: apexX - VeloMark.armX, y: 512 - VeloMark.armY),
                         radius: VeloMark.apexRadius)
            drawn.addLine(to: CGPoint(x: apexX - VeloMark.armX, y: 512 - VeloMark.armY))

            let a = fromIcon.boundingBox, b = drawn.cgPath.boundingBox
            #expect(abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5,
                    "chevron at \(apexX) starts in a different place")
            #expect(abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5,
                    "chevron at \(apexX) is a different size")
        }
    }

    /// Fitted to whatever it is given, keeping the icon's proportions.
    @Test func theMarkFitsTheFrameItIsGiven() {
        let box = CGRect(x: 0, y: 0, width: 200, height: 120)
        let fitted = VeloMark().path(in: box).boundingRect

        #expect(fitted.width <= box.width + 0.5)
        #expect(fitted.height <= box.height + 0.5)
        // Centred, not parked in a corner.
        #expect(abs(fitted.midX - box.midX) < 0.5)
        #expect(abs(fitted.midY - box.midY) < 0.5)
    }

    @Test func aFrameOfNothingDoesNotDivideByZero() {
        _ = VeloMark().path(in: .zero)
    }
}
