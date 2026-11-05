import ReytKit
import SwiftUI

/// One week's review. Sections in order: reflection slot, coverage and score, moods, comparison, highest and
/// lowest days, workouts, "more of this". Everything is computed from the records, so it is always current.
struct ReviewView: View {
    let store: JournalStore
    let events: JournalEvents

    @State private var model: ReviewModel
    @State private var today = AppClock.today()
    @Environment(\.scenePhase) private var scenePhase

    init(weekStart: DateKey, store: JournalStore, events: JournalEvents) {
        self.store = store
        self.events = events
        _model = State(initialValue: ReviewModel(weekStart: weekStart, store: store, events: events))
    }

    private static let endAnchor = "end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(Copy.Reviews.weekOf(range))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(Color("ink"))
                        .accessibilityAddTraits(.isHeader)
                    if model.loadFailed {
                        Button(Copy.Reviews.loadFailed) { Task { await model.refresh() } }
                            .font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
                    } else if let stats = model.stats {
                        sections(stats)
                    }
                    Color.clear.frame(height: 1).id(Self.endAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: model.isLoaded) { await scrollToEndIfRequested(proxy) }
        }
        .background(Color("paper"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: events.contentRevision) { await model.refresh() }
        .onDisappear { model.flush() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = AppClock.today() } else { model.flush() }
        }
    }

    private var range: String {
        DateRangeFormat.string(
            from: model.weekStart, to: model.weekStart.adding(days: 6), today: today)
    }

    private func scrollToEndIfRequested(_ proxy: ScrollViewProxy) async {
        #if DEBUG
            // Simulator-only: `-scrollReviewToEnd` brings the bottom of the review into view for screenshots.
            guard CommandLine.arguments.contains("-scrollReviewToEnd"), model.isLoaded else { return }
            try? await Task.sleep(for: .milliseconds(500))
            proxy.scrollTo(Self.endAnchor, anchor: .bottom)
        #endif
    }

    @ViewBuilder private func sections(_ stats: WeeklyStats) -> some View {
        if stats.recordedDays == 0 {
            Text(Copy.Reviews.emptyWeek).font(.body).foregroundStyle(Color("inkSecondary"))
        } else {
            // S13 replaces this slot with the generated reflection.
            Text(Copy.Reviews.reflectionPlaceholder)
                .font(.body).foregroundStyle(Color("inkSecondary"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("hairline"), lineWidth: 1))
            scoreSection(stats)
            moodSection(stats)
            comparisonSection(stats)
            extremesSection(stats)
        }
        workoutSection(stats.workouts)
        MoreOfThisSection(model: model, today: today)
    }

    // MARK: Score

    private func scoreSection(_ stats: WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(Copy.Reviews.scoresTitle)
            Text(Copy.Reviews.coverage(stats.recordedDays)).font(.footnote).foregroundStyle(Color("inkSecondary"))
            if let average = stats.averageScoreDisplay {
                Text(Copy.Reviews.average(average, scoredDays: stats.scoredDays))
                    .font(.body).foregroundStyle(Color("ink"))
                ScoreChart(points: stats.chart, scoredDays: stats.scoredDays, today: today)
                    .padding(.top, 8)
            } else {
                Text(Copy.Reviews.noScores).font(.body).foregroundStyle(Color("inkSecondary"))
            }
        }
    }

    // MARK: Moods

    private func moodSection(_ stats: WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(Copy.Reviews.moodsTitle)
            if stats.noMoods {
                Text(Copy.Reviews.noMoods).font(.body).foregroundStyle(Color("inkSecondary"))
            } else {
                MoodBars(moods: stats.moodFrequency)
            }
        }
    }

    // MARK: Comparison

    @ViewBuilder private func comparisonSection(_ stats: WeeklyStats) -> some View {
        let score = stats.scoreComparison
        let moods = stats.moodComparison
        if score != nil || moods != nil {
            VStack(alignment: .leading, spacing: 8) {
                heading(Copy.Reviews.comparisonTitle)
                if let score {
                    Text(
                        Copy.Reviews.comparisonScore(
                            average: WeeklyStats.display(tenths: score.thisAverageTenths), days: score.thisScoredDays,
                            lastAverage: WeeklyStats.display(tenths: score.previousAverageTenths),
                            lastDays: score.previousScoredDays)
                    )
                    .font(.body).foregroundStyle(Color("ink"))
                }
                if let moods {
                    ForEach(moods, id: \.moodID) { m in
                        Text(
                            Copy.Reviews.comparisonMood(
                                label: MoodCatalog.label(for: m.moodID) ?? m.moodID, count: m.thisCount, of: m.thisOf,
                                lastCount: m.previousCount, lastOf: m.previousOf)
                        )
                        .font(.body).foregroundStyle(Color("ink"))
                    }
                }
            }
        }
    }

    // MARK: Highest and lowest

    @ViewBuilder private func extremesSection(_ stats: WeeklyStats) -> some View {
        if !stats.highestDays.isEmpty || !stats.lowestDays.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                dayLinks(
                    title: Copy.Reviews.highestTitle(count: stats.highestDays.count), days: stats.highestDays,
                    stats: stats)
                dayLinks(
                    title: Copy.Reviews.lowestTitle(count: stats.lowestDays.count), days: stats.lowestDays, stats: stats
                )
            }
        }
    }

    @ViewBuilder private func dayLinks(title: String, days: [DateKey], stats: WeeklyStats) -> some View {
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                heading(title)
                ForEach(days, id: \.self) { day in
                    let score = stats.chart.first { $0.dateKey == day }?.score.flatMap { DayScore($0) }
                    NavigationLink(value: ReviewRoute.day(day)) {
                        HStack {
                            Text([Copy.History.rowDate(day), score?.label].compactMap { $0 }.joined(separator: ", "))
                                .font(.body).foregroundStyle(Color("accent"))
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint(Copy.Reviews.openDayHint)
                }
            }
        }
    }

    // MARK: Workouts

    @ViewBuilder private func workoutSection(_ workouts: WeeklyStats.WorkoutTotals) -> some View {
        if workouts.count > 0 {
            VStack(alignment: .leading, spacing: 4) {
                heading(Copy.Workouts.title)
                Text(
                    Copy.Reviews.workoutSummary(
                        count: workouts.count, duration: Copy.Workouts.duration(seconds: workouts.totalDurationSeconds))
                )
                .font(.body).foregroundStyle(Color("ink"))
                ForEach(workouts.distances, id: \.kind) { total in
                    Text(
                        Copy.Reviews.distanceLine(
                            distance: Copy.Workouts.distance(meters: total.meters, swimming: total.kind == .swimming),
                            kind: total.kind)
                    )
                    .font(.footnote).foregroundStyle(Color("inkSecondary"))
                }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color("ink"))
            .accessibilityAddTraits(.isHeader)
    }
}
