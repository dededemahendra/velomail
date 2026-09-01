import SwiftUI

/// The app's mark: two rounded chevrons, the same pair as the icon.
///
/// Drawn here rather than shared with `VeloIcon`, which is build-time tooling
/// the app deliberately does not link -- it exists to run `actool`, and pulling
/// it in would drag the whole icon pipeline into the shipped binary. The
/// geometry is duplicated on purpose and `VeloMarkTests` compares the two, so
/// the copy cannot quietly drift from the icon it is meant to echo.
struct VeloMark: Shape {
    /// Matches `AppIconRenderer`: arms 200 across and 250 up, apex rounded by
    /// 88, on a 1024 canvas.
    static let armX: CGFloat = 200
    static let armY: CGFloat = 250
    static let apexRadius: CGFloat = 88
    static let apexes: [CGFloat] = [470, 740]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for apexX in Self.apexes {
            path.move(to: CGPoint(x: apexX - Self.armX, y: 512 + Self.armY))
            path.addArc(tangent1End: CGPoint(x: apexX, y: 512),
                        tangent2End: CGPoint(x: apexX - Self.armX, y: 512 - Self.armY),
                        radius: Self.apexRadius)
            path.addLine(to: CGPoint(x: apexX - Self.armX, y: 512 - Self.armY))
        }

        // Laid out on the icon's 1024 canvas, then fitted to whatever it is
        // given, so the two chevrons keep the icon's proportions at any size.
        let bounds = path.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return path }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        return path
            .applying(CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY))
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }
}

/// The mark, stroked in the icon's gradient.
struct VeloMarkView: View {
    var side: CGFloat = 64
    /// Proportional to the mark, so it thickens with it rather than turning
    /// into a hairline on a large one.
    private var lineWidth: CGFloat { side * 0.155 }

    var body: some View {
        VeloMark()
            .stroke(LinearGradient(colors: [Color(red: 0.85, green: 0.27, blue: 0.94),
                                            Color(red: 0.49, green: 0.36, blue: 0.96),
                                            Color(red: 0.13, green: 0.60, blue: 0.87)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side * 0.78)
            .accessibilityHidden(true)
    }
}
