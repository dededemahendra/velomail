import SwiftUI

enum Banner {
    /// How wide a banner is allowed to get.
    ///
    /// A toast is read in one glance. Left to fill the window, an archive
    /// confirmation put its icon on the far left and its Undo button on the far
    /// right, and learning that one thread had moved meant travelling the whole
    /// width of the screen. Each of these is an `HStack` with a `Spacer` in it,
    /// so without a cap they take every point on offer.
    static let maxWidth: CGFloat = 460
}

extension View {
    /// Keeps a floating banner to a readable width.
    func bannerWidth() -> some View {
        frame(maxWidth: Banner.maxWidth)
    }
    /// The surface anything floating over the mail sits on.
    ///
    /// Liquid Glass where the system has it, and the material it replaced
    /// everywhere else. Shared rather than written per banner: three floating
    /// things with three slightly different grounds looks like an accident,
    /// and they appear together -- a failed send above an undo above a notice.
    ///
    /// A glass or material surface alone was not enough. These float over the
    /// split, with the dark list on one side and a message body on the other,
    /// and an HTML mail is usually white. The same toast came out dark on its
    /// left half and near-white on its right, with "Undo" on a ground barely
    /// distinguishable from its own text -- it was legible or not depending on
    /// which message happened to be open behind it.
    ///
    /// So the content sits on a defined ground and the glass goes behind that:
    /// enough of it to keep an edge and a sense of depth, not enough to decide
    /// whether the words can be read. `windowBackgroundColor` rather than a
    /// fixed dark, so it follows the appearance the text colour follows.
    @ViewBuilder
    func floatingSurface(cornerRadius: CGFloat = 12,
                         shadow: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let ground = Color(nsColor: .windowBackgroundColor).opacity(0.92)

        if #available(macOS 26.0, *) {
            self.background(ground, in: shape)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.22), radius: shadow, y: shadow / 3)
        } else {
            self.background(ground, in: shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: shadow, y: shadow / 3)
        }
    }
}
