import ReytKit
import SwiftUI

/// The day score as a star that fills from the bottom (viewBox 40): one fifth per score point, five is a full
/// star. Draws only the glyph, in the inherited foreground colour; the caller supplies the circle behind it and
/// the size (34 inside a 56 circle, 25 in 38, 19 in 28).
struct ScoreGlyph: View {
    let score: DayScore
    var size: CGFloat = 34
    /// Outline width in viewBox units.
    var strokeUnits: CGFloat = 2.6

    fileprivate nonisolated static let viewBox: CGFloat = 40
    fileprivate nonisolated static let centre = CGPoint(x: 20, y: 21)
    fileprivate nonisolated static let outer: CGFloat = 14
    private static let top: CGFloat = 7
    private static var bottom: CGFloat { centre.y + outer * CGFloat(sin(54.0 * Double.pi / 180)) }

    var body: some View {
        let scale = size / Self.viewBox
        let span = Self.bottom - Self.top
        let fillTop = (Self.bottom - CGFloat(score.rawValue) / 5 * span) * scale
        ZStack {
            StarShape().fill(.foreground)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: size, height: size - fillTop)
                        .offset(y: fillTop)
                }
            StarShape().stroke(
                .foreground, style: StrokeStyle(lineWidth: strokeUnits / Self.viewBox * size, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The five-point star in viewBox 40 units, scaled into the rect.
    private struct StarShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / ScoreGlyph.viewBox
            var path = Path()
            for i in 0..<10 {
                let radius = i.isMultiple(of: 2) ? ScoreGlyph.outer : 6.6
                let angle = (-90.0 + 36.0 * Double(i)) * Double.pi / 180
                let point = CGPoint(
                    x: rect.minX + (ScoreGlyph.centre.x + radius * CGFloat(cos(angle))) * scale,
                    y: rect.minY + (ScoreGlyph.centre.y + radius * CGFloat(sin(angle))) * scale)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }
}
