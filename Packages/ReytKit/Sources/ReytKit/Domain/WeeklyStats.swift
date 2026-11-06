import Foundation

/// One day's worth of what the statistics need, detached from the store.
public struct DayInput: Sendable, Equatable {
    public var dateKey: DateKey
    /// `DayContent.hasUserContent` for the day (A3), the only definition of "recorded".
    public var hasUserContent: Bool
    public var score: Int?
    public var moodIDs: [String]

    public init(dateKey: DateKey, hasUserContent: Bool, score: Int?, moodIDs: [String] = []) {
        self.dateKey = dateKey
        self.hasUserContent = hasUserContent
        self.score = score
        self.moodIDs = moodIDs
    }

    public init(dateKey: DateKey, content: DayContent) {
        self.init(
            dateKey: dateKey, hasUserContent: content.hasUserContent, score: content.dayScore,
            moodIDs: content.moodIDs)
    }
}

/// One week's days and workouts, the input to `WeeklyStats.compute`.
public struct WeekInput: Sendable, Equatable {
    public var days: [DayInput]
    public var workouts: [WorkoutSnapshotValue]
    public init(days: [DayInput], workouts: [WorkoutSnapshotValue]) {
        self.days = days
        self.workouts = workouts
    }
}

/// Weekly review statistics. Pure and recomputed live, so edits, imports and deletions show immediately.
/// Missing values are unknown, never zero: a day with no score is simply not a scored day.
public struct WeeklyStats: Sendable, Equatable {
    /// A headline comparison needs at least this many observations in each of the two weeks.
    public static let minimumObservationsForComparison = 3

    public struct ChartPoint: Sendable, Equatable {
        public let dateKey: DateKey
        /// nil when the day has no rating (leave a gap, never draw zero).
        public let score: Int?
    }

    public struct MoodCount: Sendable, Equatable {
        public let moodID: String
        /// Distinct days on which this mood was logged.
        public let dayCount: Int
        /// Days with at least one mood logged that week.
        public let of: Int
    }

    public struct ScoreComparison: Sendable, Equatable {
        public let thisAverage: Double
        public let previousAverage: Double
        /// Raw difference (this minus previous).
        public let delta: Double
        /// Difference between the two displayed (rounded) averages, in tenths, so the shown numbers agree.
        public let deltaTenths: Int
        /// The two averages as displayed (rounded half-up, in tenths).
        public let thisAverageTenths: Int
        public let previousAverageTenths: Int
        public let thisScoredDays: Int
        public let previousScoredDays: Int
    }

    public struct DistanceTotal: Sendable, Equatable {
        public let kind: WorkoutActivity.DistanceKind
        public let meters: Double
    }

    public struct WorkoutTotals: Sendable, Equatable {
        /// Display-deduplicated groups, so a watch plus Strava copy of one run counts once.
        public let count: Int
        public let totalDurationSeconds: Double
        /// Only kinds with at least one recorded distance, in a fixed order.
        public let distances: [DistanceTotal]
    }

    public let weekStart: DateKey
    /// Days with user content, out of 7.
    public let recordedDays: Int
    public let daysInWeek = 7
    public let scoredDays: Int
    /// Raw mean of the recorded scores, nil with no scored days.
    public let averageScore: Double?
    /// The mean rounded half-up to one decimal place, in tenths (34 means 3.4).
    public let averageScoreTenths: Int?
    /// Seven points, Sunday to Saturday.
    public let chart: [ChartPoint]
    public let moodLoggedDays: Int
    /// Catalog order first, then unknown IDs in first-seen order.
    public let moodFrequency: [MoodCount]
    /// True when no day that week has a mood ("no moods recorded this week").
    public let noMoods: Bool
    public let scoreComparison: ScoreComparison?
    public let workouts: WorkoutTotals

    /// "3.4", or nil with no scored days.
    public var averageScoreDisplay: String? { averageScoreTenths.map(Self.display(tenths:)) }

    /// "3.4" for 34.
    public static func display(tenths: Int) -> String {
        "\(tenths / 10).\(tenths % 10)"
    }

    /// Mean of `sum / count` rounded half-up to tenths using integer arithmetic (no binary-float drift).
    /// 3.25 gives 33 and 3.35 gives 34. `count` must be positive.
    public static func roundedTenths(sum: Int, count: Int) -> Int {
        (20 * sum + count) / (2 * count)
    }

    public static func compute(
        weekStart: DateKey, days: [DayInput], workouts: [WorkoutSnapshotValue],
        previous: (days: [DayInput], workouts: [WorkoutSnapshotValue])? = nil
    ) -> WeeklyStats {
        let this = Measures(weekStart: weekStart, days: days)
        let prevStart = WeekCalendar.previousWeekStart(before: weekStart)
        let prev = previous.map { Measures(weekStart: prevStart, days: $0.days) }

        let scores = this.scores
        let sum = scores.values.reduce(0, +)
        let tenths = scores.isEmpty ? nil : roundedTenths(sum: sum, count: scores.count)
        let average = scores.isEmpty ? nil : Double(sum) / Double(scores.count)

        let min = minimumObservationsForComparison
        var scoreComparison: ScoreComparison?
        if let prev, scores.count >= min, prev.scores.count >= min, let average, let tenths {
            let prevSum = prev.scores.values.reduce(0, +)
            let prevAverage = Double(prevSum) / Double(prev.scores.count)
            let prevTenths = roundedTenths(sum: prevSum, count: prev.scores.count)
            scoreComparison = ScoreComparison(
                thisAverage: average, previousAverage: prevAverage, delta: average - prevAverage,
                deltaTenths: tenths - prevTenths, thisAverageTenths: tenths, previousAverageTenths: prevTenths,
                thisScoredDays: scores.count,
                previousScoredDays: prev.scores.count)
        }

        return WeeklyStats(
            weekStart: weekStart, recordedDays: this.recorded, scoredDays: scores.count, averageScore: average,
            averageScoreTenths: tenths,
            chart: (0..<7).map {
                let key = weekStart.adding(days: $0)
                return ChartPoint(dateKey: key, score: scores[key])
            },
            moodLoggedDays: this.moodDays.count,
            moodFrequency: MoodCatalog.normalize(this.moodOrder).map {
                MoodCount(moodID: $0, dayCount: this.moodCounts[$0] ?? 0, of: this.moodDays.count)
            },
            noMoods: this.moodDays.isEmpty, scoreComparison: scoreComparison, workouts: totals(workouts))
    }

    private static func totals(_ workouts: [WorkoutSnapshotValue]) -> WorkoutTotals {
        let groups = WorkoutDedupe.collapse(workouts)
        var duration = 0.0
        var meters: [WorkoutActivity.DistanceKind: Double] = [:]
        for g in groups {
            duration += g.representative.durationSeconds
            guard let kind = WorkoutActivity(id: g.representative.activityType).distanceKind,
                // The representative may lack a distance that another source recorded.
                let d = g.members.lazy.compactMap(\.distanceMeters).first
            else { continue }
            meters[kind, default: 0] += d
        }
        let order: [WorkoutActivity.DistanceKind] = [.walkingRunning, .cycling, .swimming]
        return WorkoutTotals(
            count: groups.count, totalDurationSeconds: duration,
            distances: order.compactMap { k in meters[k].map { DistanceTotal(kind: k, meters: $0) } })
    }

    /// Per-week observations, restricted to the seven days of the week.
    private struct Measures {
        var recorded = 0
        var scores: [DateKey: Int] = [:]
        var moodDays: Set<DateKey> = []
        var moodCounts: [String: Int] = [:]
        var moodOrder: [String] = []

        init(weekStart: DateKey, days: [DayInput]) {
            let range = weekStart...weekStart.adding(days: 6)
            var seen = Set<DateKey>()
            for d in days.sorted(by: { $0.dateKey < $1.dateKey }) where range.contains(d.dateKey) {
                guard seen.insert(d.dateKey).inserted else { continue }
                if d.hasUserContent { recorded += 1 }
                if let s = d.score, DayScore(s) != nil { scores[d.dateKey] = s }
                let moods = MoodCatalog.normalize(d.moodIDs)
                if !moods.isEmpty { moodDays.insert(d.dateKey) }
                for m in moods {
                    if moodCounts[m] == nil { moodOrder.append(m) }
                    moodCounts[m, default: 0] += 1
                }
            }
        }
    }
}
