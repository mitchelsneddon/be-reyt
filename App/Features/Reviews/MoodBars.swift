import ReytKit
import SwiftUI

/// Mood frequency as horizontal bars: how many of the mood-logged days each mood appeared on. One neutral
/// colour for every mood (a mood is a category, not a grade), and bar length is count over the denominator.
struct MoodBars: View {
    let moods: [WeeklyStats.MoodCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(moods, id: \.moodID) { mood in
                let text = Copy.Reviews.moodRow(
                    label: MoodCatalog.label(for: mood.moodID) ?? mood.moodID, count: mood.dayCount, of: mood.of)
                VStack(alignment: .leading, spacing: 6) {
                    Text(text).font(.body).foregroundStyle(Color("ink"))
                    bar(fraction: mood.of > 0 ? Double(mood.dayCount) / Double(mood.of) : 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        Capsule()
            .fill(Color("hairline"))
            .frame(height: 10)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Color("inkSecondary")).frame(width: proxy.size.width * fraction)
                }
            }
    }
}
