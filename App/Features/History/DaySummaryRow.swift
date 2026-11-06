import ReytKit
import SwiftUI

/// One history row: day number over weekday, the first line as a title, the next line as a snippet, a photo count
/// and the day's score as a face circle (no circle when unscored).
struct DaySummaryRow: View {
    let summary: DaySummary

    @ScaledMetric(relativeTo: .title2) private var dayWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text("\(summary.dateKey.day)")
                    .brFont(.dayNum)
                    .foregroundStyle(Palette.ink)
                Text(Copy.History.weekdayShort(summary.dateKey))
                    .brFont(.label)
                    .foregroundStyle(Palette.ink2)
            }
            .frame(width: dayWidth)
            VStack(alignment: .leading, spacing: 1) {
                if !lines.title.isEmpty {
                    Text(lines.title)
                        .brFont(.rowTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
                if !lines.snippet.isEmpty {
                    Text(lines.snippet)
                        .brFont(.rowSnippet)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            photoCount
            if let score {
                Circle().fill(Palette.score(score))
                    .frame(width: circle, height: circle)
                    .overlay {
                        FaceGlyph(score: score, size: circle * 19 / 28, strokeUnits: 2.8)
                            .foregroundStyle(Palette.faceInk)
                    }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var score: DayScore? { summary.content.dayScore.flatMap { DayScore(rawValue: $0) } }

    @ViewBuilder private var photoCount: some View {
        let photos = summary.content.attachmentCount
        if photos > 0 {
            HStack(spacing: 4) {
                Image(systemName: "photo").accessibilityHidden(true)
                Text("\(photos)")
            }
            .brFont(.label)
            .foregroundStyle(Palette.ink2)
        }
    }

    /// The title is the first nonblank line (the same line `DaySummary.preview` returns); the snippet is the next
    /// nonblank line of that same field, so a one-line day has a title only.
    private var lines: (title: String, snippet: String) {
        let fields = [
            summary.content.text, summary.content.smileAnswer, summary.content.rotatingAnswer,
            summary.planText, summary.followUpNote,
        ].compactMap { $0 }
        for field in fields {
            let found =
                field
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let first = found.first { return (first, found.dropFirst().first ?? "") }
        }
        return ("", "")
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
