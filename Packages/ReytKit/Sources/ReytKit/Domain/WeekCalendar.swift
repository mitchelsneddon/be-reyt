import Foundation

/// Review weeks run Sunday to Saturday. With `DateKey`, the only place week ranges are computed (A4).
public enum WeekCalendar {
    /// The Sunday on or before `key`.
    public static func reviewWeekStart(containing key: DateKey) -> DateKey {
        key.adding(days: -key.weekday)
    }

    /// The Saturday ending the review week containing `key`.
    public static func reviewWeekEnd(containing key: DateKey) -> DateKey {
        reviewWeekStart(containing: key).adding(days: 6)
    }

    /// First day on which the week starting `weekStart` is unlocked (the following Sunday).
    public static func unlockKey(forWeekStart weekStart: DateKey) -> DateKey {
        weekStart.adding(days: 7)
    }

    public static func isUnlocked(weekStart: DateKey, today: DateKey) -> Bool {
        today >= unlockKey(forWeekStart: weekStart)
    }

    public static func previousWeekStart(before weekStart: DateKey) -> DateKey {
        weekStart.adding(days: -7)
    }

    /// The week a Sunday "one thing for next week" plan targets: Monday after to the following Sunday.
    /// Returns nil when `sunday` is not a Sunday.
    public static func intentionTarget(forSunday sunday: DateKey) -> (start: DateKey, end: DateKey)? {
        guard sunday.weekday == 0 else { return nil }
        return (sunday.adding(days: 1), sunday.adding(days: 7))
    }

    /// "More of this" targets the Sunday to Saturday week containing the day it was first saved.
    public static func moreOfThisTarget(savedOn key: DateKey) -> (start: DateKey, end: DateKey) {
        (reviewWeekStart(containing: key), reviewWeekEnd(containing: key))
    }
}
