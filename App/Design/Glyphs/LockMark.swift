import SwiftUI

/// The sunrise mark on the lock screen: an accentSoft disc with an accent horizon and rays (viewBox 56).
struct LockMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(Palette.accentSoft)
            SVGPathShape(
                "M13 35h30M19 35a9 9 0 0 1 18 0M28 15v5M16.5 20.5l3.2 3.2M39.5 20.5l-3.2 3.2M23 41h10",
                viewBox: 56
            )
            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.2 / 56 * size, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
