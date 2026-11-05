import Charts
import ReytKit
import SwiftUI

/// Sunday to Saturday day scores on a fixed 1 to 5 axis. A point per scored day, a line only between
/// neighbouring scored days, so a missing day is a real gap (never a zero, never a line across it).
struct ScoreChart: View {
    let points: [WeeklyStats.ChartPoint]
    let scoredDays: Int
    var today: DateKey

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    private struct Plotted: Identifiable {
        let id: DateKey
        let label: String
        let score: Int
        /// Which contiguous run of scored days this point belongs to.
        let run: Int
    }

    private var plotted: [Plotted] {
        var result: [Plotted] = []
        var run = 0
        var previousWasScored = false
        for (index, point) in points.enumerated() {
            guard let score = point.score else {
                if previousWasScored { run += 1 }
                previousWasScored = false
                continue
            }
            result.append(
                Plotted(id: point.dateKey, label: Copy.Reviews.weekdayShort[index % 7], score: score, run: run))
            previousWasScored = true
        }
        return result
    }

    var body: some View {
        let data = plotted
        Chart {
            ForEach(data) { p in
                LineMark(
                    x: .value("day", p.label), y: .value("score", p.score), series: .value("run", p.run)
                )
                .foregroundStyle(Color("accent"))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .accessibilityHidden(true)
            }
            ForEach(data) { p in
                PointMark(x: .value("day", p.label), y: .value("score", p.score))
                    .foregroundStyle(Color("accent"))
                    .symbolSize(70)
                    .accessibilityLabel(
                        Copy.Reviews.pointLabel(
                            date: Copy.History.rowDate(p.id), score: DayScore(p.score) ?? .okay))
            }
        }
        .chartXScale(domain: Copy.Reviews.weekdayShort)
        .chartYScale(domain: 1...5)
        .chartXAxis {
            AxisMarks(values: Copy.Reviews.weekdayShort) { _ in
                AxisValueLabel().foregroundStyle(Color("inkSecondary"))
            }
        }
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine().foregroundStyle(Color("hairline"))
                // At accessibility sizes the end labels would take most of the width, so only the grid remains.
                if !typeSize.isAccessibilitySize, let v = value.as(Int.self), v == 1 || v == 5,
                    let score = DayScore(v)
                {
                    AxisValueLabel { Text(score.label).font(.caption2).foregroundStyle(Color("inkSecondary")) }
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel(Copy.Reviews.chartLabel)
        .accessibilityValue(Copy.Reviews.chartSummary(scoredDays: scoredDays))
    }
}
