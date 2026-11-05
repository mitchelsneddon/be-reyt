import Foundation

/// A persisted review row, reduced to what eligibility needs.
public struct ReviewRowInfo: Sendable, Equatable {
    public var weekStart: DateKey
    public var unlockedAt: Date
    public init(weekStart: DateKey, unlockedAt: Date) {
        self.weekStart = weekStart
        self.unlockedAt = unlockedAt
    }
}

/// Which weeks the reviews list shows. A week never relocks: a persisted row keeps its week listed even if
/// `today` later moves backwards (westward travel).
public struct ReviewEligibility: Sendable, Equatable {
    public let today: DateKey
    public let earliestContentDay: DateKey?
    public let persisted: [ReviewRowInfo]

    public init(today: DateKey, earliestContentDay: DateKey?, persisted: [ReviewRowInfo]) {
        self.today = today
        self.earliestContentDay = earliestContentDay
        self.persisted = persisted
    }

    /// The newest week unlocked as of `today`.
    public var latestEligibleWeek: DateKey {
        WeekCalendar.reviewWeekStart(containing: today.adding(days: -7))
    }

    /// Every week from the one holding the earliest content through the latest eligible week, plus every
    /// persisted week. Newest first.
    public func listedWeeks() -> [DateKey] {
        var weeks = Set(persisted.map { WeekCalendar.reviewWeekStart(containing: $0.weekStart) })
        if let earliest = earliestContentDay {
            var week = WeekCalendar.reviewWeekStart(containing: earliest)
            let last = latestEligibleWeek
            while week <= last {
                weeks.insert(week)
                week = week.adding(days: 7)
            }
        }
        return weeks.sorted(by: >)
    }

    /// Listed weeks with no persisted row yet; the caller creates their rows.
    public func newlyEligible() -> [DateKey] {
        let have = Set(persisted.map { WeekCalendar.reviewWeekStart(containing: $0.weekStart) })
        return listedWeeks().filter { !have.contains($0) }
    }
}
