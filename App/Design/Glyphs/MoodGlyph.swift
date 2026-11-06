import SwiftUI

/// Mood icons (viewBox 24), stroked in the inherited foreground colour. "tired" (retired) and any unknown id
/// fall back to an SF Symbol so legacy entries still show something.
struct MoodGlyph: View {
    let id: String
    var size: CGFloat = 26
    /// Stroke width in viewBox units.
    var strokeUnits: CGFloat = 1.9

    private static let paths: [String: [String]] = [
        "happy": [
            "M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4",
            "M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0z",
        ],
        "sad": [
            "M12 20s-7.5-4.6-7.5-10.1A4.2 4.2 0 0 1 12 7.3a4.2 4.2 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z",
            "M12 7.3l-1.7 3.5 2.8 2.1-1.6 3.4",
        ],
        "stressed": ["M13 2.5L5.5 13.5h5.5l-1 8 7.5-11h-5.5z"],
        "annoyed": [
            "M12 21a6 6 0 0 0 6-6c0-4-3-6-4.5-10-1 2.5-2 3.5-3 4-.5-1-1-1.5-2-2C7.5 9 6 11.5 6 15a6 6 0 0 0 6 6z",
            "M12 21a2.5 2.5 0 0 1-2.5-2.5c0-1.8 1.5-2.5 2.5-4.5 1 2 2.5 2.7 2.5 4.5A2.5 2.5 0 0 1 12 21z",
        ],
        "anxious": [
            "M12 4c4.5 0 7.5 3 7.5 7s-4 8-8 8-7-3-7-6.5 3.5-6 7-6 5.5 2.5 5.5 5-2.5 4.5-5 4.5-4-1.5-4-3.5 1.8-3 3.5-3 2.5 1 2.5 2.5"
        ],
    ]

    static func hasGlyph(_ id: String) -> Bool { paths[id] != nil }

    var body: some View {
        Group {
            if let shapes = Self.paths[id] {
                let style = StrokeStyle(lineWidth: strokeUnits / 24 * size, lineCap: .round, lineJoin: .round)
                ZStack {
                    ForEach(shapes, id: \.self) { d in
                        SVGPathShape(d, viewBox: 24).stroke(.foreground, style: style)
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
