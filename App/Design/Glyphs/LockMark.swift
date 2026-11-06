import SwiftUI

/// The app icon in miniature: the tilted page whose last line ends in the gold dot, on the midnight tile.
/// viewBox 100, the same geometry as scripts/make-icon.swift. Used on the lock, waiting and privacy screens and
/// beside the onboarding wordmark.
struct LockMark: View {
    var size: CGFloat = 56

    var body: some View {
        let unit = size / 100
        ZStack {
            RoundedRectangle(cornerRadius: 22.37 * unit, style: .continuous).fill(Palette.iconGround)
            ZStack {
                RoundedRectangle(cornerRadius: 4.5 * unit).fill(Palette.iconPage)
                    .frame(width: 46 * unit, height: 62 * unit)
                SVGPathShape("M35 35h30M35 45h30M35 55h18", viewBox: 100)
                    .stroke(Palette.iconGround, style: StrokeStyle(lineWidth: 3.2 * unit, lineCap: .round))
                GlyphDots(points: [CGPoint(x: 60, y: 55)], radius: 3.8, viewBox: 100).fill(Palette.wordmarkDot)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-6))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
