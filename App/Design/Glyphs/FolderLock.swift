import SwiftUI

/// The onboarding backup hero: a folder with a padlock (viewBox 24, stroke 1.7) at 40pt inside an 88pt
/// accentSoft disc. `size` is the disc; the glyph keeps the board's 40/88 ratio.
struct FolderLock: View {
    var size: CGFloat = 88

    var body: some View {
        let glyph = size * 40 / 88
        ZStack {
            Circle().fill(Palette.accentSoft)
            SVGPathShape(
                "M3.5 7a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"
                    + "M9.5 17v-2.5h5V17zM10.5 14.5v-1a1.5 1.5 0 0 1 3 0v1",
                viewBox: 24
            )
            .stroke(
                Palette.accent,
                style: StrokeStyle(lineWidth: 1.7 / 24 * glyph, lineCap: .round, lineJoin: .round)
            )
            .frame(width: glyph, height: glyph)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
