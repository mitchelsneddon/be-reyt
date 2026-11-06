import ReytKit
import SwiftUI

/// "how was your day?": five 56 pt faces. Tap selects, tap the selected one clears.
/// No red/green: the five score colours are a calm ramp, and the value is also written out under each face.
struct DayScoreControl: View {
    let score: DayScore?
    let onChange: (DayScore?) -> Void

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let colors = [Palette.score1, Palette.score2, Palette.score3, Palette.score4, Palette.score5]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(Copy.Day.scoreTitle)
            faces
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.Day.scoreLabel)
                .accessibilityValue(score.map(Copy.Day.scoreName) ?? Copy.Day.scoreNotSet)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        onChange(score.flatMap { DayScore($0.rawValue + 1) } ?? score ?? .veryDifficult)
                    case .decrement:
                        onChange(score.flatMap { DayScore($0.rawValue - 1) })
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: Copy.Day.scoreClear) { onChange(nil) }
        }
    }

    private var faces: some View {
        // Five do not fit once labels scale. At accessibility sizes the faces wrap into two columns (3 rows),
        // because even 3 per row cannot hold a scaled "difficult" without breaking the word.
        let count = typeSize.isAccessibilitySize ? 2 : 5
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: count),
            alignment: .center, spacing: 12
        ) {
            ForEach(DayScore.allCases, id: \.self) { face($0) }
        }
    }

    private func face(_ value: DayScore) -> some View {
        let isOn = value == score
        let color = Self.colors[value.rawValue - 1]
        let size = min(circle, 72)
        return Button {
            onChange(isOn ? nil : value)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if isOn {
                        // A 3 pt paper gap, then a 2 pt ring in the score colour.
                        Circle().fill(color).padding(-5)
                        Circle().fill(Palette.paper).padding(-3)
                    }
                    Circle().fill(isOn ? color : Palette.chip)
                    FaceGlyph(score: value, size: size * 34 / 56, strokeUnits: 2.6)
                        .foregroundStyle(isOn ? Palette.faceInk : Palette.ink3)
                }
                .frame(width: size, height: size)
                .padding(5)
                Text(Copy.Day.scoreName(value))
                    .brFont(isOn ? .faceLabelBold : .faceLabel)
                    .foregroundStyle(isOn ? Palette.ink : Palette.ink2)
                    .multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : labelWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}
