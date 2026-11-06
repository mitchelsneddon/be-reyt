import ReytKit
import SwiftUI

/// Five circles for the optional day score. Tap selects, tap the selected one clears.
/// No red/green: selection is an accent fill, the value is also written out.
struct DayScoreControl: View {
    let score: DayScore?
    let onChange: (DayScore?) -> Void

    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(DayScore.allCases, id: \.self) { value in
                    Button {
                        onChange(value == score ? nil : value)
                    } label: {
                        Circle()
                            .fill(value == score ? Palette.accent : Color.clear)
                            .overlay(
                                Circle().strokeBorder(
                                    value == score ? Palette.accent : Palette.ink2, lineWidth: 1.5)
                            )
                            .frame(width: min(dot, 44), height: min(dot, 44))  // five must fit a 375 pt width at AX5
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
            }
            Text(score.map(Copy.Day.scoreName) ?? Copy.Day.scorePrompt)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
        }
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
