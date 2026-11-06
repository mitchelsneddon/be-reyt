import SwiftUI

/// Filled circles in viewBox units.
struct GlyphDots: Shape {
    let points: [CGPoint]
    let radius: CGFloat
    let viewBox: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        var path = Path()
        for p in points {
            path.addEllipse(
                in: CGRect(
                    x: rect.minX + (p.x - radius) * scale, y: rect.minY + (p.y - radius) * scale,
                    width: radius * 2 * scale, height: radius * 2 * scale))
        }
        return path
    }
}
