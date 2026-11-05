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

    /// Saves the user's "a little more of next week" answer for a review. The target week (the Sunday to Saturday
    /// week containing `savedOn`) is stored on the first nonblank save and never moves afterwards. A blank value
    /// clears the text only. This is the user's own text, never model input, so no narrative is purged. A review
    /// row that does not exist yet is created, so a save is never lost.
    public func saveMoreOfThis(weekStart: DateKey, text: String, savedOn: DateKey) throws -> StoreEffect {
        try requireWritable()
        let week = WeekCalendar.reviewWeekStart(containing: weekStart)
        let s = week.string
        var d = FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })
        d.fetchLimit = 1
        let nonblank = DayContent.isNonblank(text)
        let row: WeeklyReview
        if let existing = try modelContext.fetch(d).first {
            row = existing
        } else {
            guard nonblank else { return StoreEffect() }
            row = WeeklyReview(
                weekStartKey: s, weekEndKey: week.adding(days: 6).string, timeZoneID: timeZone.identifier,
                unlockedAt: clock())
            modelContext.insert(row)
        }
        let newText: String? = nonblank ? text : nil
        let needsTarget = nonblank && row.moreOfThisTargetStartKey == nil
        guard row.moreOfThisText != newText || needsTarget else { return StoreEffect() }
        row.moreOfThisText = newText
        if needsTarget {
            let target = WeekCalendar.moreOfThisTarget(savedOn: savedOn)
            row.moreOfThisTargetStartKey = target.start.string
            row.moreOfThisTargetEndKey = target.end.string
        }
        return try commit(candidateDays: [], before: [:], bumpDays: [])
    }

    /// The saved "more of this" answer and its target week for a review, nil when nothing was ever saved.
    public func moreOfThis(weekStart: DateKey) throws -> MoreOfThis? {
        let s = WeekCalendar.reviewWeekStart(containing: weekStart).string
        var d = FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })
        d.fetchLimit = 1
        guard let row = try modelContext.fetch(d).first else { return nil }
        return MoreOfThis(
            text: row.moreOfThisText ?? "", targetStart: row.moreOfThisTargetStartKey.flatMap { DateKey($0) },
            targetEnd: row.moreOfThisTargetEndKey.flatMap { DateKey($0) })
    }
}

public struct MoreOfThis: Sendable, Equatable {
    public let text: String
    public let targetStart: DateKey?
    public let targetEnd: DateKey?
}
