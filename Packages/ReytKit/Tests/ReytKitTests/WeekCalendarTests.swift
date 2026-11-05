import Testing

@testable import ReytKit

private func k(_ s: String) -> DateKey { DateKey(s)! }

@Suite("WeekCalendar")
struct WeekCalendarTests {
    @Test("week of 1-7 Nov 2026 starts Sunday 1 Nov and unlocks 8 Nov")
    func weekBounds() {
        for day in 1...7 {
            let key = k("2026-11-0\(day)")
            #expect(WeekCalendar.reviewWeekStart(containing: key) == k("2026-11-01"))
            #expect(WeekCalendar.reviewWeekEnd(containing: key) == k("2026-11-07"))
        }
        #expect(WeekCalendar.reviewWeekStart(containing: k("2026-11-08")) == k("2026-11-08"))
        #expect(WeekCalendar.unlockKey(forWeekStart: k("2026-11-01")) == k("2026-11-08"))
    }

    @Test("unlock boundary")
    func unlock() {
        let start = k("2026-11-01")
        #expect(!WeekCalendar.isUnlocked(weekStart: start, today: k("2026-11-07")))
        #expect(WeekCalendar.isUnlocked(weekStart: start, today: k("2026-11-08")))
        #expect(WeekCalendar.isUnlocked(weekStart: start, today: k("2027-02-01")))
        #expect(!WeekCalendar.isUnlocked(weekStart: start, today: k("2026-10-01")))
    }

    @Test("previous week start crosses year")
    func previous() {
        #expect(WeekCalendar.previousWeekStart(before: k("2026-11-01")) == k("2026-10-25"))
        #expect(WeekCalendar.previousWeekStart(before: k("2027-01-03")) == k("2026-12-27"))
    }

    @Test("Sunday intention targets the following Monday to Sunday")
    func intention() throws {
        let t = try #require(WeekCalendar.intentionTarget(forSunday: k("2026-11-08")))
        #expect(t.start == k("2026-11-09"))
        #expect(t.end == k("2026-11-15"))
    }

    @Test(
        "non-Sunday intention source returns nil",
        arguments: [
            "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07",
        ])
    func intentionNil(_ s: String) {
        #expect(WeekCalendar.intentionTarget(forSunday: k(s)) == nil)
    }

    @Test("more-of-this targets the Sunday to Saturday week of the save date")
    func moreOfThis() {
        let t = WeekCalendar.moreOfThisTarget(savedOn: k("2026-11-18"))
        #expect(t.start == k("2026-11-15"))
        #expect(t.end == k("2026-11-21"))
        let sunday = WeekCalendar.moreOfThisTarget(savedOn: k("2026-11-15"))
        #expect(sunday.start == k("2026-11-15") && sunday.end == k("2026-11-21"))
    }
}
