import Foundation
import SwiftData
import Testing

@testable import ReytKit

private func day(_ s: String) -> DateKey { DateKey(s)! }

private func makeStore() throws -> JournalStore {
    let container = try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return JournalStore(
        modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
        timeZone: TimeZone(identifier: "UTC")!)
}

@Suite("Review eligibility")
struct ReviewEligibilityTests {
    private func listed(today: String, earliest: String?, persisted: [String] = []) -> [DateKey] {
        ReviewEligibility(
            today: day(today), earliestContentDay: earliest.map(day),
            persisted: persisted.map { ReviewRowInfo(weekStart: day($0), unlockedAt: Date(timeIntervalSince1970: 0)) }
        ).listedWeeks()
    }

    @Test("the week of 2026-11-01 to 07 is listed from Sunday 2026-11-08, not on Saturday 2026-11-07")
    func unlockBoundary() {
        #expect(listed(today: "2026-11-07", earliest: "2026-11-02").contains(day("2026-11-01")) == false)
        #expect(listed(today: "2026-11-08", earliest: "2026-11-02") == [day("2026-11-01")])
    }

    @Test("a persisted row keeps its week listed when today moves back (westward travel)")
    func westwardTravel() {
        let weeks = listed(today: "2026-11-07", earliest: "2026-11-02", persisted: ["2026-11-01"])
        #expect(weeks == [day("2026-11-01")])
    }

    @Test("earliest content 2026-10-03 lists from 2026-09-27 to the latest eligible week, newest first")
    func range() {
        let weeks = listed(today: "2026-11-10", earliest: "2026-10-03")
        #expect(
            weeks == [
                day("2026-11-01"), day("2026-10-25"), day("2026-10-18"), day("2026-10-11"), day("2026-10-04"),
                day("2026-09-27"),
            ])
    }

    @Test("an empty journal lists nothing, and persisted rows still list")
    func emptyJournal() {
        #expect(listed(today: "2026-11-10", earliest: nil).isEmpty)
        #expect(listed(today: "2026-11-10", earliest: nil, persisted: ["2026-10-04"]) == [day("2026-10-04")])
    }

    @Test("a persisted week older than the earliest content is unioned in, without duplicates")
    func union() {
        let weeks = listed(today: "2026-11-10", earliest: "2026-10-20", persisted: ["2026-10-04", "2026-10-18"])
        #expect(weeks == [day("2026-11-01"), day("2026-10-25"), day("2026-10-18"), day("2026-10-04")])
    }

    @Test("newlyEligible is the listed weeks without a persisted row")
    func newlyEligible() {
        let e = ReviewEligibility(
            today: day("2026-11-10"), earliestContentDay: day("2026-10-20"),
            persisted: [ReviewRowInfo(weekStart: day("2026-10-25"), unlockedAt: Date(timeIntervalSince1970: 0))])
        #expect(e.newlyEligible() == [day("2026-11-01"), day("2026-10-18")])
    }

    @Test("ensureReviewRows creates missing rows once; a second call creates nothing and is not dirty")
    func ensureIdempotent() async throws {
        let store = try makeStore()
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try await store.ensureReviewRows(
            for: [day("2026-11-01"), day("2026-10-25")], unlockedAt: at, timeZoneID: "UTC")
        #expect(first.dirty)
        let rows = try await store.reviewRows().sorted { $0.weekStart < $1.weekStart }
        #expect(rows.map(\.weekStart) == [day("2026-10-25"), day("2026-11-01")])
        #expect(rows.allSatisfy { $0.unlockedAt == at })

        let later = Date(timeIntervalSince1970: 1_800_000_000)
        let second = try await store.ensureReviewRows(
            for: [day("2026-11-01"), day("2026-10-25")], unlockedAt: later, timeZoneID: "UTC")
        #expect(second == StoreEffect())
        #expect(!second.dirty)
        let after = try await store.reviewRows()
        #expect(after.count == 2)
        // Never relocks or rewrites the original unlock time.
        #expect(after.allSatisfy { $0.unlockedAt == at })
    }

    @Test("weekInput reflects live edits and counts only DayContent days")
    func weekInputLive() async throws {
        let store = try makeStore()
        _ = try await store.updateEntry(day("2026-11-02"), .score(.good))
        _ = try await store.updateEntry(day("2026-11-03"), .moods(["happy", "tired"]))
        _ = try await store.assignPromptIfNeeded(day("2026-11-04")) { _, _ in PromptChoice(id: "p", text: "t") }
        _ = try await store.updateEntry(day("2026-11-09"), .text("next week"))

        var input = try await store.weekInput(weekStart: day("2026-11-01"))
        #expect(input.days.count == 7)
        var stats = WeeklyStats.compute(weekStart: day("2026-11-01"), days: input.days, workouts: input.workouts)
        #expect(stats.recordedDays == 2)
        #expect(stats.scoredDays == 1)
        #expect(stats.averageScoreDisplay == "4.0")
        #expect(stats.moodLoggedDays == 1)

        _ = try await store.updateEntry(day("2026-11-02"), .score(nil))
        input = try await store.weekInput(weekStart: day("2026-11-01"))
        stats = WeeklyStats.compute(weekStart: day("2026-11-01"), days: input.days, workouts: input.workouts)
        #expect(stats.scoredDays == 0)
        #expect(stats.averageScore == nil)
        #expect(stats.recordedDays == 1)
    }

    @Test("earliestContentDay ignores prompt-only days")
    func earliest() async throws {
        let store = try makeStore()
        #expect(try await store.earliestContentDay() == nil)
        _ = try await store.assignPromptIfNeeded(day("2026-10-01")) { _, _ in PromptChoice(id: "p", text: "t") }
        _ = try await store.updateEntry(day("2026-10-03"), .text("hi"))
        _ = try await store.updateEntry(day("2026-10-09"), .text("hi"))
        #expect(try await store.earliestContentDay() == day("2026-10-03"))
    }
}
