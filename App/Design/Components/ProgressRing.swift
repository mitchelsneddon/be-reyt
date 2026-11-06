import SwiftUI

/// A spinner ring: an accent arc over a `chip` track. Static when Reduce Motion is on.
struct ProgressRing: View {
    var size: CGFloat = 28
    var lineWidth: CGFloat = 3
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Palette.chip, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
        }
        .accessibilityHidden(true)
    }
}
