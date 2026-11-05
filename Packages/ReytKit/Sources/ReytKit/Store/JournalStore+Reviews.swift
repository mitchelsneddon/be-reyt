import Foundation
import SwiftData

/// Review eligibility rows and the week inputs the statistics read. Nothing here generates anything.
extension JournalStore {
    /// Creates the `WeeklyReview` row for each week that lacks one, recording range, zone and `unlockedAt`.
    /// Existing rows are never touched (a week never relocks), so a second call changes nothing and returns an
    /// empty effect.
    public func ensureReviewRows(for weekStarts: [DateKey], unlockedAt: Date, timeZoneID: String) throws
        -> StoreEffect
    {
        try requireWritable()
        var inserted = false
        var handled = Set<DateKey>()
        for raw in weekStarts {
            let week = WeekCalendar.reviewWeekStart(containing: raw)
            guard handled.insert(week).inserted else { continue }
            let s = week.string
            var d = FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })
            d.fetchLimit = 1
            if try modelContext.fetch(d).first != nil { continue }
            modelContext.insert(
                WeeklyReview(
                    weekStartKey: s, weekEndKey: week.adding(days: 6).string, timeZoneID: timeZoneID,
                    unlockedAt: unlockedAt))
            inserted = true
        }
        guard inserted else { return StoreEffect() }
        return try commit(candidateDays: [], before: [:], bumpDays: [])
    }

    public func reviewRows() throws -> [ReviewRowInfo] {
        try modelContext.fetch(FetchDescriptor<WeeklyReview>()).compactMap { row in
            DateKey(row.weekStartKey).map { ReviewRowInfo(weekStart: $0, unlockedAt: row.unlockedAt) }
        }
    }

    /// The earliest day with user content (`DayContent.hasUserContent`), or nil for an empty journal.
    public func earliestContentDay() throws -> DateKey? {
        try historyDays().last?.dateKey
    }

    /// The seven days (Sunday to Saturday) and the stored workouts for the review week containing `weekStart`.
    public func weekInput(weekStart: DateKey) throws -> WeekInput {
        let start = WeekCalendar.reviewWeekStart(containing: weekStart)
        let lo = start.string
        let hi = start.adding(days: 6).string
        let days = try (0..<7).map { offset -> DayInput in
            let key = start.adding(days: offset)
            return DayInput(dateKey: key, content: try dayContent(key))
        }
        let workouts = try modelContext.fetch(
            FetchDescriptor<WorkoutSnapshot>(predicate: #Predicate { $0.dateKey >= lo && $0.dateKey <= hi })
        ).map(WorkoutSnapshotValue.init)
        return WeekInput(days: days, workouts: workouts)
    }
}
