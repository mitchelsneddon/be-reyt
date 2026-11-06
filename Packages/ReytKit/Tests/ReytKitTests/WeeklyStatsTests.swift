import Foundation
import Testing

@testable import ReytKit

private func day(_ s: String) -> DateKey { DateKey(s)! }

/// 2026-11-01 is a Sunday.
private let week = day("2026-11-01")
private let prevWeek = day("2026-10-25")

private func input(
    _ start: DateKey, scores: [Int?] = [], moods: [[String]] = [], content: Set<Int>? = nil
) -> [DayInput] {
    (0..<7).map { i in
        let score = i < scores.count ? scores[i] : nil
        let m = i < moods.count ? moods[i] : []
        let has = content?.contains(i) ?? (score != nil || !m.isEmpty)
        return DayInput(dateKey: start.adding(days: i), hasUserContent: has, score: score, moodIDs: m)
    }
}

private func stats(_ days: [DayInput], prev: [DayInput]? = nil, workouts: [WorkoutSnapshotValue] = []) -> WeeklyStats {
    WeeklyStats.compute(
        weekStart: week, days: days, workouts: workouts, previous: prev.map { ($0, []) })
}

private func workout(
    _ id: Int, source: String, type: String = "running", startOffset: TimeInterval, duration: TimeInterval,
    meters: Double?
) -> WorkoutSnapshotValue {
    let start = Date(timeIntervalSince1970: 1_793_000_000 + startOffset)
    return WorkoutSnapshotValue(
        healthKitUUID: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", id))")!,
        sourceName: source, activityType: type, start: start, end: start.addingTimeInterval(duration),
        durationSeconds: duration, distanceMeters: meters)
}

@Suite("Weekly stats")
struct WeeklyStatsTests {
    @Test("no ratings: no average, zero scored days, empty chart, no comparison")
    func noRatings() {
        let s = stats(input(week), prev: input(prevWeek, scores: [3, 3, 3]))
        #expect(s.averageScore == nil)
        #expect(s.averageScoreDisplay == nil)
        #expect(s.scoredDays == 0)
        #expect(s.chart.count == 7)
        #expect(s.chart.allSatisfy { $0.score == nil })
        #expect(s.scoreComparison == nil)
        #expect(s.highestDays.isEmpty && s.lowestDays.isEmpty)
    }

    @Test("one rating gives that average over one scored day, with no extremes")
    func oneRating() {
        let s = stats(input(week, scores: [nil, nil, 4]))
        #expect(s.scoredDays == 1)
        #expect(s.averageScore == 4.0)
        #expect(s.averageScoreDisplay == "4.0")
        #expect(s.highestDays.isEmpty && s.lowestDays.isEmpty)
    }

    @Test("seven ratings 1,2,3,4,5,5,4 average 3.4 and the chart runs Sunday to Saturday")
    func sevenRatings() {
        let s = stats(input(week, scores: [1, 2, 3, 4, 5, 5, 4]))
        #expect(s.scoredDays == 7)
        #expect(s.averageScoreDisplay == "3.4")
        #expect(s.chart.map(\.score) == [1, 2, 3, 4, 5, 5, 4])
        #expect(s.chart.first?.dateKey == day("2026-11-01"))
        #expect(s.chart.last?.dateKey == day("2026-11-07"))
        #expect(s.recordedDays == 7)
    }

    @Test("missing ratings leave gaps, never zero")
    func gaps() {
        let s = stats(input(week, scores: [2, nil, 4, nil, nil, nil, 5]))
        #expect(s.chart.map(\.score) == [2, nil, 4, nil, nil, nil, 5])
        #expect(s.scoredDays == 3)
        #expect(s.averageScore == 11.0 / 3.0)
        #expect(s.averageScoreDisplay == "3.7")
    }

    @Test("rounding is half up, not banker's: 3.25 shows 3.3 and 3.35 shows 3.4")
    func halfUp() {
        let s = stats(input(week, scores: [3, 3, 3, 4]))
        #expect(s.averageScore == 3.25)
        #expect(s.averageScoreDisplay == "3.3")
        // 67 over 20 days cannot fit in one week, so check the rounding rule directly.
        #expect(WeeklyStats.display(tenths: WeeklyStats.roundedTenths(sum: 67, count: 20)) == "3.4")
        // 2.25 is where banker's rounding would go to 2.2.
        #expect(WeeklyStats.display(tenths: WeeklyStats.roundedTenths(sum: 9, count: 4)) == "2.3")
    }

    @Test("a retired mood stored on a day is still counted, after the active ones")
    func retiredMoodCounted() {
        let s = stats(input(week, moods: [["tired"], ["anxious", "tired"], ["sad"]]))
        #expect(s.moodFrequency.map(\.moodID) == ["sad", "anxious", "tired"])
        #expect(s.moodFrequency.first { $0.moodID == "tired" }?.dayCount == 2)
        #expect(s.moodLoggedDays == 3)
    }

    @Test("multiple moods per day count by distinct day and can exceed days in total")
    func multipleMoods() {
        let s = stats(input(week, moods: [["happy", "tired"], ["happy", "tired"], ["happy"]]))
        #expect(s.moodLoggedDays == 3)
        #expect(s.moodFrequency.map(\.moodID) == ["happy", "tired"])
        #expect(s.moodFrequency.map(\.dayCount) == [3, 2])
        #expect(s.moodFrequency.allSatisfy { $0.of == 3 })
        #expect(!s.noMoods)
    }

    @Test("a duplicate mood ID on one day counts once")
    func duplicateMoods() {
        let s = stats(input(week, moods: [["happy", "happy"], ["stressed"]]))
        #expect(s.moodFrequency.first { $0.moodID == "happy" }?.dayCount == 1)
        #expect(s.moodLoggedDays == 2)
    }

    @Test("mood order follows the catalog, then unknown IDs")
    func moodOrder() {
        let s = stats(input(week, moods: [["zzz", "annoyed"], ["happy", "future-mood"]]))
        #expect(s.moodFrequency.map(\.moodID) == ["happy", "annoyed", "zzz", "future-mood"])
    }

    @Test("no moods recorded sets the flag, and mood coverage is separate from score coverage")
    func noMoods() {
        let s = stats(input(week, scores: [3, 4]))
        #expect(s.noMoods)
        #expect(s.moodLoggedDays == 0)
        #expect(s.moodFrequency.isEmpty)
        #expect(s.scoredDays == 2)
    }

    @Test("mood-logged days and scored days are counted separately")
    func separateCoverage() {
        let s = stats(input(week, scores: [3, nil, nil], moods: [[], ["happy"], ["happy"]]))
        #expect(s.scoredDays == 1)
        #expect(s.moodLoggedDays == 2)
        #expect(s.recordedDays == 3)
    }

    @Test("ties are included in highest and lowest")
    func ties() {
        let s = stats(input(week, scores: [5, 2, 3, 5, 2, 4]))
        #expect(s.highestDays == [day("2026-11-01"), day("2026-11-04")])
        #expect(s.lowestDays == [day("2026-11-02"), day("2026-11-05")])
    }

    @Test("all scores equal gives no highest or lowest")
    func allEqual() {
        let s = stats(input(week, scores: [3, 3, 3, 3]))
        #expect(s.highestDays.isEmpty)
        #expect(s.lowestDays.isEmpty)
    }

    @Test("score comparison is suppressed under three scored days in either week")
    func comparisonThreshold() {
        let this = input(week, scores: [4, 4, 4])
        #expect(stats(this, prev: input(prevWeek, scores: [2, 2])).scoreComparison == nil)
        #expect(stats(input(week, scores: [4, 4]), prev: input(prevWeek, scores: [2, 2, 2])).scoreComparison == nil)
        #expect(stats(this, prev: nil).scoreComparison == nil)

        let c = stats(this, prev: input(prevWeek, scores: [2, 2, 3])).scoreComparison
        #expect(c?.thisScoredDays == 3)
        #expect(c?.previousScoredDays == 3)
        #expect(c?.thisAverage == 4.0)
        #expect(c?.previousAverage == 7.0 / 3.0)
        #expect(c?.deltaTenths == 40 - 23)
    }

    @Test("unequal coverage is reported with both counts, not hidden")
    func unequalCoverage() {
        let c = stats(input(week, scores: [3, 3, 3, 3, 3, 3, 3]), prev: input(prevWeek, scores: [3, 3, 3]))
            .scoreComparison
        #expect(c?.thisScoredDays == 7)
        #expect(c?.previousScoredDays == 3)
        #expect(c?.deltaTenths == 0)
    }

    @Test("mood comparison carries each week's denominator and needs three mood-logged days in both")
    func moodComparison() {
        let this = input(week, moods: [["happy"], ["happy", "tired"], ["tired"], ["happy"]])
        let prev = input(prevWeek, moods: [["happy"], ["stressed"], ["happy"]])
        let c = stats(this, prev: prev).moodComparison
        #expect(c?.map(\.moodID) == ["happy", "stressed", "tired"])
        let happy = c?.first { $0.moodID == "happy" }
        #expect(happy?.thisCount == 3 && happy?.thisOf == 4)
        #expect(happy?.previousCount == 2 && happy?.previousOf == 3)
        let stressed = c?.first { $0.moodID == "stressed" }
        #expect(stressed?.thisCount == 0 && stressed?.previousCount == 1)

        let thin = input(prevWeek, moods: [["happy"], ["happy"]])
        #expect(stats(this, prev: thin).moodComparison == nil)
        #expect(stats(input(week, moods: [["happy"], ["happy"]]), prev: prev).moodComparison == nil)
    }

    @Test("score and mood comparisons gate independently")
    func independentGates() {
        let this = input(week, scores: [4, 4, 4], moods: [["happy"]])
        let prev = input(prevWeek, scores: [3, 3, 3], moods: [["happy"]])
        let s = stats(this, prev: prev)
        #expect(s.scoreComparison != nil)
        #expect(s.moodComparison == nil)
    }

    @Test("removing a day's score recomputes the average and counts")
    func editRecomputes() {
        var days = input(week, scores: [5, 5, 2])
        #expect(stats(days).averageScoreDisplay == "4.0")
        #expect(stats(days).scoredDays == 3)
        days[0].score = nil
        let after = stats(days)
        #expect(after.scoredDays == 2)
        #expect(after.averageScoreDisplay == "3.5")
        #expect(after.chart[0].score == nil)
    }

    @Test("a day outside the week is ignored")
    func outsideWeek() {
        var days = input(week, scores: [3])
        days.append(DayInput(dateKey: day("2026-11-08"), hasUserContent: true, score: 5))
        let s = stats(days)
        #expect(s.scoredDays == 1)
        #expect(s.recordedDays == 1)
    }

    @Test("coverage counts only days with user content; a prompt-only day is not recorded")
    func coverage() {
        let days = input(week, content: [0, 2])
        #expect(stats(days).recordedDays == 2)
        #expect(stats(input(week, content: [])).recordedDays == 0)
        #expect(stats(days).daysInWeek == 7)
    }

    @Test("a COROS and Strava copy of one run counts once in the totals")
    func workoutDuplicates() {
        let coros = workout(1, source: "COROS", startOffset: 0, duration: 1800, meters: 5000)
        let strava = workout(2, source: "Strava", startOffset: 5, duration: 1795, meters: 5010)
        let ride = workout(3, source: "COROS", type: "cycling", startOffset: 86_400, duration: 3600, meters: 20_000)
        let lift = workout(4, source: "COROS", type: "strength", startOffset: 172_800, duration: 2400, meters: nil)
        let s = stats(input(week), workouts: [coros, strava, ride, lift])
        #expect(s.workouts.count == 3)
        #expect(s.workouts.totalDurationSeconds == 1800 + 3600 + 2400)
        #expect(s.workouts.distances.map(\.kind) == [.walkingRunning, .cycling])
        #expect(s.workouts.distances.map(\.meters) == [5000, 20_000])
    }

    @Test("an empty week with workouts shows coverage 0 of 7 and the workouts")
    func emptyWeekWithWorkouts() {
        let s = stats(input(week), workouts: [workout(1, source: "COROS", startOffset: 0, duration: 600, meters: 1000)])
        #expect(s.recordedDays == 0)
        #expect(s.daysInWeek == 7)
        #expect(s.workouts.count == 1)
        #expect(s.noMoods)
        #expect(s.averageScore == nil)
    }

    @Test("no workouts gives zero totals")
    func noWorkouts() {
        let s = stats(input(week))
        #expect(s.workouts.count == 0)
        #expect(s.workouts.totalDurationSeconds == 0)
        #expect(s.workouts.distances.isEmpty)
    }
}
