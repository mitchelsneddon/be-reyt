import ReytKit
import SwiftUI

/// The five day-score faces (viewBox 40). Draws only the glyph, in the inherited foreground colour; the caller
/// supplies the circle behind it and the size (34 inside a 56 circle, 25 in 38, 19 in 28).
struct FaceGlyph: View {
    let score: DayScore
    var size: CGFloat = 34
    /// Stroke width in viewBox units: 2.6 at the large size, 2.8 for the small ones.
    var strokeUnits: CGFloat = 2.6

    private struct Parts {
        let strokes: [String]
        let eyes: [CGPoint]
        let filledMouth: String?
    }

    private static let eyesAt17 = [CGPoint(x: 14.5, y: 17), CGPoint(x: 25.5, y: 17)]

    private var parts: Parts {
        switch score {
        case .veryDifficult:
            Parts(
                strokes: ["M11 12.5l5 2M29 12.5l-5 2", "M13 29.5q7-7 14 0"],
                eyes: [CGPoint(x: 14.5, y: 18), CGPoint(x: 25.5, y: 18)], filledMouth: nil)
        case .difficult:
            Parts(strokes: ["M14 28q6-4 12 0"], eyes: Self.eyesAt17, filledMouth: nil)
        case .okay:
            Parts(strokes: ["M14.5 26.5h11"], eyes: Self.eyesAt17, filledMouth: nil)
        case .good:
            Parts(strokes: ["M13.5 24.5q6.5 6 13 0"], eyes: Self.eyesAt17, filledMouth: nil)
        case .excellent:
            Parts(
                strokes: ["M11.5 17.5q3-4 6 0M22.5 17.5q3-4 6 0"], eyes: [],
                filledMouth: "M12.5 23h15q-1.5 8-7.5 8t-7.5-8z")
        }
    }

    var body: some View {
        let parts = parts
        let style = StrokeStyle(lineWidth: strokeUnits / 40 * size, lineCap: .round, lineJoin: .round)
        ZStack {
            ForEach(parts.strokes, id: \.self) { d in
                SVGPathShape(d, viewBox: 40).stroke(.foreground, style: style)
            }
            if let mouth = parts.filledMouth {
                SVGPathShape(mouth, viewBox: 40).fill(.foreground)
                SVGPathShape(mouth, viewBox: 40).stroke(.foreground, style: style)
            }
            if !parts.eyes.isEmpty {
                GlyphDots(points: parts.eyes, radius: 1.6, viewBox: 40).fill(.foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

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
