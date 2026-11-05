import ReytKit
import SwiftUI

/// The written reflection at the top of a review. Always started by the reader. Every state keeps the statistics
/// below it visible, so a failure never hides the numbers.
struct ReflectionSection: View {
    let model: ReflectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.state {
            case .loading:
                EmptyView()
            case .notGenerated:
                intro
                writeButton
            case .generating:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(Copy.WeekReflection.generating).font(.body).foregroundStyle(Color("inkSecondary"))
                }
                .accessibilityElement(children: .combine)
            case .ready(let content, let newer):
                ready(content, newerPromptAvailable: newer)
            case .unavailable(let reason):
                note(Copy.WeekReflection.failure(reason))
                Button(Copy.WeekReflection.tryAgain) { Task { await model.recheck() } }
                    .font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
            case .failed(let reason):
                note(Copy.WeekReflection.failure(reason))
                if reason != .noEntries { writeButton }
            case .purged:
                note(Copy.WeekReflection.purged)
                writeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("hairline"), lineWidth: 1))
        .animation(.default, value: model.state)
    }

    private var intro: some View {
        Text(Copy.WeekReflection.intro).font(.footnote).foregroundStyle(Color("inkSecondary"))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.body).foregroundStyle(Color("inkSecondary"))
    }

    private var writeButton: some View {
        Button {
            Task { await model.generate() }
        } label: {
            Text(Copy.WeekReflection.write)
                .font(.body.weight(.medium))
                .foregroundStyle(Color("accent"))
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityHint(Copy.WeekReflection.writeHint)
    }

    // MARK: Ready

    @ViewBuilder private func ready(_ content: WeeklyReflectionContent, newerPromptAvailable: Bool) -> some View {
        Text(content.overview)
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color("ink"))
            .fixedSize(horizontal: false, vertical: true)
        points(title: Copy.WeekReflection.highlights, content.highlights)
        points(title: Copy.WeekReflection.difficult, content.difficult)
        if !content.themes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                heading(Copy.WeekReflection.themes)
                ForEach(Array(content.themes.enumerated()), id: \.offset) { _, theme in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color("ink"))
                        Text(theme.summary).font(.body).foregroundStyle(Color("ink"))
                            .fixedSize(horizontal: false, vertical: true)
                        DateChips(dates: theme.dateKeys)
                    }
                }
            }
        }
        if !content.questions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading(Copy.WeekReflection.questions)
                ForEach(Array(content.questions.enumerated()), id: \.offset) { _, q in
                    Text(q).font(.system(.body, design: .serif).italic()).foregroundStyle(Color("inkSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        Text(Copy.WeekReflection.footnote).font(.caption).foregroundStyle(Color("inkSecondary"))
        if newerPromptAvailable {
            Button(Copy.WeekReflection.regenerate) { Task { await model.generate() } }
                .font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
                .accessibilityHint(Copy.WeekReflection.regenerateHint)
        }
    }

    @ViewBuilder private func points(title: String, _ points: [WeeklyReflectionContent.Point]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                heading(title)
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.text).font(.body).foregroundStyle(Color("ink"))
                            .fixedSize(horizontal: false, vertical: true)
                        DateChips(dates: p.dateKeys)
                    }
                }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(Color("ink")).accessibilityAddTraits(.isHeader)
    }
}

/// Small tappable dates under a point or theme, each opening that day's page.
private struct DateChips: View {
    let dates: [DateKey]

    var body: some View {
        if !dates.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(dates, id: \.self) { key in
                    NavigationLink(value: ReviewRoute.day(key)) {
                        Text(Copy.History.rowDate(key))
                            .font(.caption)
                            .foregroundStyle(Color("accent"))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(Capsule().strokeBorder(Color("hairline"), lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Copy.History.rowDate(key))
                    .accessibilityHint(Copy.Reviews.openDayHint)
                }
            }
        }
    }
}
