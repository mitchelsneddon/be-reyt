import ReytKit
import SwiftUI

/// One history row: lowercase date, first line, and quiet indicators for photos, score and moods.
/// No colour for the score; it is a word, not a grade.
struct DaySummaryRow: View {
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.History.rowDate(summary.dateKey))
                .font(.footnote)
                .foregroundStyle(Color("inkSecondary"))
            if !summary.preview.isEmpty {
                Text(summary.preview)
                    .font(.body)
                    .foregroundStyle(Color("ink"))
                    .lineLimit(2)
            }
            indicators
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var score: DayScore? { summary.content.dayScore.flatMap { DayScore(rawValue: $0) } }

    @ViewBuilder private var indicators: some View {
        let photos = summary.content.attachmentCount
        let moods = summary.content.moodIDs.count
        if photos > 0 || score != nil || moods > 0 {
            HStack(spacing: 12) {
                if photos > 0 { indicator("photo", "\(photos)") }
                if let score { indicator("gauge.with.dots.needle.33percent", score.label) }
                if moods > 0 { indicator("face.smiling", "\(moods)") }
            }
            .font(.caption)
            .foregroundStyle(Color("inkSecondary"))
        }
    }

    private func indicator(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
    }

    private var accessibilityText: String {
        var parts = [Copy.History.rowLabel(date: Copy.History.rowDate(summary.dateKey), preview: summary.preview)]
        if summary.content.attachmentCount > 0 {
            parts.append(Copy.History.photosLabel(summary.content.attachmentCount))
        }
        if let score { parts.append(Copy.History.scoreLabel(score)) }
        if !summary.content.moodIDs.isEmpty { parts.append(Copy.History.moodsLabel(summary.content.moodIDs.count)) }
        return parts.joined(separator: ", ")
    }
}
