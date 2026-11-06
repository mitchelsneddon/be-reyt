import SwiftUI

/// Feeling icons as faces (viewBox 24): stroked outlines and features plus filled parts (eye dots, a tear), all in
/// the inherited foreground colour. Unknown ids fall back to an SF Symbol so legacy entries still show something.
struct MoodGlyph: View {
    let id: String
    var size: CGFloat = 26
    /// Stroke width in viewBox units.
    var strokeUnits: CGFloat = 1.6

    private struct Parts {
        var strokes: [String]
        var dots: [CGPoint] = []
        var dotRadius: CGFloat = 1.05
        var filled: [String] = []
    }

    private static let round = "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0z"
    private static let smaller = "M2.5 13a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0-17 0z"

    private static let parts: [String: Parts] = [
        "happy": Parts(strokes: [round, "M8.2 10.6q1.3-1.5 2.6 0M13.2 10.6q1.3-1.5 2.6 0M8 14q4 4.5 8 0"]),
        "sad": Parts(
            strokes: [round, "M9 16.6q3-2.6 6 0"],
            dots: [CGPoint(x: 9, y: 10.5), CGPoint(x: 15, y: 10.5)],
            filled: ["M15 12.7c-.6.9-.85 1.5-.85 1.9a.85.85 0 0 0 1.7 0c0-.4-.25-1-.85-1.9z"]),
        "stressed": Parts(
            strokes: [
                smaller, "M7.5 16.6l1.2-1.1 1.15 1.1 1.15-1.1 1.15 1.1 1.15-1.1 1.2 1.1",
                "M20 2.6c-.8 1.1-1.1 1.8-1.1 2.3a1.1 1.1 0 0 0 2.2 0c0-.5-.3-1.2-1.1-2.3z",
            ],
            dots: [CGPoint(x: 8.3, y: 11.6), CGPoint(x: 13.7, y: 11.6)]),
        "annoyed": Parts(
            strokes: [round, "M7.6 8.4l3 1.1M16.4 8.4l-3 1.1M9.4 16.3l5.2-.8"],
            dots: [CGPoint(x: 9.2, y: 11.8), CGPoint(x: 14.8, y: 11.8)]),
        "anxious": Parts(
            strokes: [round, "M7.8 9.1l2.6-1.3M16.2 9.1l-2.6-1.3M8.6 16.2q.85-.9 1.7 0t1.7 0 1.7 0 1.7 0"],
            dots: [CGPoint(x: 9.3, y: 11.7), CGPoint(x: 14.7, y: 11.7)], dotRadius: 1.3),
        "excited": Parts(
            strokes: [
                smaller, "M6.9 9q1.4-1 2.8 0M12.3 9q1.4-1 2.8 0", "M7 14.6h8q-.6 4.2-4 4.2t-4-4.2z",
            ],
            dots: [CGPoint(x: 8.3, y: 11.4), CGPoint(x: 13.7, y: 11.4)],
            filled: [
                "M7 14.6h8q-.6 4.2-4 4.2t-4-4.2z",
                "M20 1.8l.65 1.55 1.55.65-1.55.65L20 6.2l-.65-1.55L17.8 4l1.55-.65z",
            ]),
        "relaxed": Parts(strokes: [round, "M8 11q1.3 1 2.6 0M13.4 11q1.3 1 2.6 0M9.5 15.2q2.5 1.8 5 0"]),
        "bored": Parts(
            strokes: [round, "M7.8 10.6h2.8M13.4 10.6h2.8M9.5 16.2h5"],
            dots: [CGPoint(x: 9.2, y: 11.7), CGPoint(x: 14.8, y: 11.7)], dotRadius: 1),
        "angry": Parts(
            strokes: [
                smaller, "M6.4 9.2l3.4 1.6M15.6 9.2l-3.4 1.6M7.6 17.4q3.4-2.8 6.8 0",
                "M17.6 3.2l.9 1.5M21.4 3.2l-.9 1.5M17.6 6.8l.9-1.5M21.4 6.8l-.9-1.5",
            ],
            dots: [CGPoint(x: 8.4, y: 12.6), CGPoint(x: 13.6, y: 12.6)]),
        "tired": Parts(strokes: [
            smaller, "M7.3 12q1.3 1 2.6 0M12.1 12q1.3 1 2.6 0M9.6 16.6h2.8M17.3 2.4h3.2l-3.2 3.4h3.2",
        ]),
    ]

    static func hasGlyph(_ id: String) -> Bool { parts[id] != nil }

    var body: some View {
        Group {
            if let parts = Self.parts[id] {
                let style = StrokeStyle(lineWidth: strokeUnits / 24 * size, lineCap: .round, lineJoin: .round)
                ZStack {
                    ForEach(parts.strokes, id: \.self) { d in
                        SVGPathShape(d, viewBox: 24).stroke(.foreground, style: style)
                    }
                    ForEach(parts.filled, id: \.self) { d in
                        SVGPathShape(d, viewBox: 24).fill(.foreground)
                    }
                    if !parts.dots.isEmpty {
                        GlyphDots(points: parts.dots, radius: parts.dotRadius, viewBox: 24).fill(.foreground)
                    }
                }
            } else {
                Image(systemName: "moon.zzz").resizable().scaledToFit().padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
