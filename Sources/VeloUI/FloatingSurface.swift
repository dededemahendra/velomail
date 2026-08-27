import SwiftUI

extension View {
    /// The surface anything floating over the mail sits on.
    ///
    /// Liquid Glass where the system has it, and the material it replaced
    /// everywhere else. Shared rather than written per banner: three floating
    /// things with three slightly different grounds looks like an accident,
    /// and they appear together -- a failed send above an undo above a notice.
    @ViewBuilder
    func floatingSurface(cornerRadius: CGFloat = 12,
                         shadow: CGFloat = 18) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.22), radius: shadow, y: shadow / 3)
        } else {
            self.background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: shadow, y: shadow / 3)
        }
    }
}
