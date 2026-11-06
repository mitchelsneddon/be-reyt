import ReytKit
import SwiftUI

/// One week's review (Sunday to Saturday). Sections in order: how the week felt, reflection, what made you smile,
/// how did that go?, activities, feelings this week, next week. A section with nothing to show is left out.
/// Everything is computed from the records, so it is always current. Nothing here writes.
struct ReviewView: View {
    let store: JournalStore
    let events: JournalEvents

    @State private var model: ReviewModel
    @State private var reflection: ReflectionModel
    @State private var didAutoGenerate = false
    /// The weekday column beside each smile answer: wide enough for "wed" in Literata italic, scaling with the type.
    @ScaledMetric(relativeTo: .body) private var dayColumn: CGFloat = 38

    init(weekStart: DateKey, store: JournalStore, events: JournalEvents) {
        self.store = store
        self.events = events
        _model = State(initialValue: ReviewModel(weekStart: weekStart, store: store))
        _reflection = State(
            initialValue: ReflectionModel(
                weekStart: WeekCalendar.reviewWeekStart(containing: weekStart), store: store, events: events))
    }

    private static let endAnchor = "end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    if model.loadFailed {
                        Button(Copy.Reviews.loadFailed) { Task { await model.refresh() } }
                            .brFont(.label).foregroundStyle(Palette.accent).frame(minHeight: 44)
                    } else if let stats = model.stats {
                        sections(stats)
                    }
                    Color.clear.frame(height: 1).id(Self.endAnchor)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: model.isLoaded) { await scrollIfRequested(proxy) }
        }
        .background(Palette.paper)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: events.contentRevision) {
            await model.refresh()
            await reflection.load()
            await autoGenerateIfRequested()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Copy.Reviews.eyebrow(weekStart: model.weekStart)).brFont(.eyebrow).foregroundStyle(Palette.ink2)
            Text(Copy.Reviews.yourWeek).brFont(.largeTitle).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.Reviews.range(from: model.weekStart, to: model.weekStart.adding(days: 6)))
                .brFont(.rowWrapping).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private func autoGenerateIfRequested() async {
        #if DEBUG
            // Simulator-only: `-autoGenerateReflection` taps "write my reflection" once, for screenshots.
            guard CommandLine.arguments.contains("-autoGenerateReflection"), !didAutoGenerate,
                reflection.state == .notGenerated
            else { return }
            didAutoGenerate = true
            await reflection.generate()
        #endif
    }

    private func scrollIfRequested(_ proxy: ScrollViewProxy) async {
        #if DEBUG
            // Simulator-only: `-scrollReviewToEnd` brings the bottom into view, and `-scrollReviewTo <section>`
            // (felt, reflection, smile, followUp, activities, feelings, next) brings that section to the top.
            let args = CommandLine.arguments
            guard model.isLoaded else { return }
            if args.contains("-scrollReviewToEnd") {
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo(Self.endAnchor, anchor: .bottom)
            } else if let i = args.firstIndex(of: "-scrollReviewTo"), args.indices.contains(i + 1) {
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo(args[i + 1], anchor: .top)
            }
        #endif
    }

    @ViewBuilder private func sections(_ stats: WeeklyStats) -> some View {
        feltSection(stats)
        if stats.recordedDays == 0 {
            Text(Copy.Reviews.emptyWeek)
                .brFont(.pointItalic).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, -8)
            activitiesSection(stats.workouts)
        } else {
            ReflectionSection(model: reflection).id("reflection")
            smileSection
            followUpSection
            activitiesSection(stats.workouts)
            feelingsSection(stats)
            nextWeekSection
        }
    }

    // MARK: How the week felt

    private func feltSection(_ stats: WeeklyStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Copy.Reviews.feltTitle)
            VStack(alignment: .leading, spacing: 0) {
                WeekFaces(chart: stats.chart)
                if stats.recordedDays > 0, let feel = WeekFeel.make(from: stats) {
                    Text(Copy.Reviews.weekFeel(feel, moodLabel: { MoodCatalog.label(for: $0) ?? $0 }))
                        .brFont(.rowWrapping).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(EdgeInsets(top: 14, leading: 8, bottom: 0, trailing: 8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
                        .padding(.top, 16)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 12, bottom: 16, trailing: 12))
            .cardSurface(padding: 0)
        }
        .id("felt")
    }

    // MARK: What made you smile

    @ViewBuilder private var smileSection: some View {
        if !model.smiles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Reviews.smileTitle)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.smiles, id: \.dateKey) { smile in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Copy.Reviews.weekdayShort[smile.dateKey.weekday])
                                .brFont(.bodyItalic).foregroundStyle(Palette.accentText)
                                .frame(width: dayColumn, alignment: .leading)
                            Text(smile.text).brFont(.body).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(Copy.Reviews.weekdayLong[smile.dateKey.weekday]), \(smile.text)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("smile")
        }
    }

    // MARK: How did that go?

    @ViewBuilder private var followUpSection: some View {
        if let plan = model.followUpPlan {
            let note = plan.followUpNote?.nonBlank
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Reviews.followUpTitle)
                HStack(alignment: .top, spacing: 10) {
                    if plan.hasFollowUpResponse { TickDisc(skipped: note == nil) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Copy.Reviews.youPlanned(plan.text)).brFont(.pointItalic).foregroundStyle(Palette.ink2)
                        if let note { Text(note).brFont(.body).foregroundStyle(Palette.ink) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("followUp")
        }
    }

    // MARK: Activities

    @ViewBuilder private func activitiesSection(_ workouts: WeeklyStats.WorkoutTotals) -> some View {
        if workouts.count > 0 {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Reviews.activitiesTitle)
                ActivitiesCard(workouts: workouts)
            }
            .id("activities")
        }
    }

    // MARK: Feelings

    @ViewBuilder private func feelingsSection(_ stats: WeeklyStats) -> some View {
        let counts = Dictionary(uniqueKeysWithValues: stats.moodFrequency.map { ($0.moodID, $0.dayCount) })
        let moods = MoodCatalog.offered(including: counts.filter { $0.value > 0 }.map(\.key))
        let unknown = stats.moodFrequency.filter { $0.dayCount > 0 && MoodCatalog.label(for: $0.moodID) == nil }
        if !stats.noMoods {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Reviews.feelingsTitle)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 5), spacing: 14
                ) {
                    ForEach(moods, id: \.id) { mood in
                        FeelingTile(id: mood.id, label: mood.label, count: counts[mood.id] ?? 0)
                    }
                    ForEach(unknown, id: \.moodID) { item in
                        FeelingTile(id: item.moodID, label: item.moodID, count: item.dayCount)
                    }
                }
            }
            .id("feelings")
        }
    }

    // MARK: Next week

    @ViewBuilder private var nextWeekSection: some View {
        if let plan = model.nextWeekPlan {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Reviews.nextWeekTitle)
                VStack(alignment: .leading, spacing: 0) {
                    if plan.text.nonBlank != nil {
                        Text(plan.text).brFont(.body).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let category = plan.category?.nonBlank {
                        Pill(text: Copy.Plan.categoryLabel(for: category)).padding(.vertical, 4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("next")
        }
    }
}

// MARK: - Pieces

/// Seven stars, Sunday to Saturday, with weekday initials under them. A day with no score is a dashed circle.
private struct WeekFaces: View {
    let chart: [WeeklyStats.ChartPoint]
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 38

    var body: some View {
        let side = min(circle, 46)
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(chart.enumerated()), id: \.offset) { index, point in
                let score = point.score.flatMap { DayScore($0) }
                VStack(spacing: 8) {
                    face(score, side: side)
                    Text(Copy.Reviews.weekdayInitials[index]).brFont(.faceLabel).foregroundStyle(Palette.ink2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Copy.Reviews.dayFaceLabel(weekday: index, score: score))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.Reviews.dayScoresLabel)
    }

    @ViewBuilder private func face(_ score: DayScore?, side: CGFloat) -> some View {
        if let score {
            Circle().fill(Palette.score(score))
                .frame(width: side, height: side)
                .overlay {
                    ScoreGlyph(score: score, size: side * 25 / 38, strokeUnits: 2.8).foregroundStyle(Palette.faceInk)
                }
        } else {
            Circle()
                .strokeBorder(Palette.ink2, style: StrokeStyle(lineWidth: 1.5, dash: [3.5, 3]))
                .frame(width: side, height: side)
        }
    }
}

/// The accent disc with a tick that marks a plan as answered (a note or a skip).
private struct TickDisc: View {
    let skipped: Bool
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 24

    var body: some View {
        Image(systemName: "checkmark")
            .symbolSize(11, weight: .heavy, relativeTo: .footnote, maxPoints: 18)
            .foregroundStyle(Palette.paper)
            .frame(width: min(side, 36), height: min(side, 36))
            .background(Palette.accent, in: Circle())
            .padding(.top, 3)
            .accessibilityLabel(skipped ? Copy.Plan.skipped : Copy.Plan.done)
    }
}

private struct ActivitiesCard: View {
    let workouts: WeeklyStats.WorkoutTotals
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 48

    private var totalMeters: Double { workouts.distances.reduce(0) { $0 + $1.meters } }
    private var onlySwimming: Bool {
        !workouts.distances.isEmpty && workouts.distances.allSatisfy { $0.kind == .swimming }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "figure.walk")
                    .symbolSize(22, maxPoints: 32)
                    .foregroundStyle(Palette.accent)
                    .frame(width: min(tile, 64), height: min(tile, 64))
                    .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .accessibilityHidden(true)
                Text("\(workouts.count)").brFont(.bigStat).foregroundStyle(Palette.ink)
                Text(Copy.Reviews.thisWeek).brFont(.rowWrapping).foregroundStyle(Palette.ink2)
            }
            HStack(alignment: .top, spacing: 16) {
                stat(Copy.Workouts.duration(seconds: workouts.totalDurationSeconds), label: Copy.Reviews.timeLabel)
                if totalMeters > 0 {
                    stat(
                        Copy.Workouts.distance(meters: totalMeters, swimming: onlySwimming),
                        label: Copy.Reviews.distanceLabel)
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 20)
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).brFont(.stat).foregroundStyle(Palette.ink)
            Text(label).brFont(.label).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct FeelingTile: View {
    let id: String
    let label: String
    let count: Int
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 56

    var body: some View {
        let on = count > 0
        VStack(spacing: 6) {
            MoodGlyph(id: id, size: 26)
                .foregroundStyle(on ? Palette.accent : Palette.ink2)
                .frame(width: min(tile, 72), height: min(tile, 72))
                .background(
                    on ? Palette.accentSoft : Palette.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("\(count)").brFont(.stat).foregroundStyle(Palette.ink)
            Text(label).brFont(.label).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Reviews.feelingLabel(label, count: count))
    }
}

extension String {
    /// Self, unless it is only whitespace.
    fileprivate var nonBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
