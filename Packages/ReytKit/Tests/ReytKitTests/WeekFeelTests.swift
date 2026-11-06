import Foundation
import SwiftData
import Testing

@testable import ReytKit

private func day(_ s: String) -> DateKey { DateKey(s)! }

/// 2026-11-01 is a Sunday.
private let week = day("2026-11-01")
private let prevWeek = day("2026-10-25")

private func days(_ start: DateKey, scores: [Int?] = [], moods: [[String]] = []) -> [DayInput] {
    (0..<7).map { i in
        let score = i < scores.count ? scores[i] : nil
        let m = i < moods.count ? moods[i] : []
        return DayInput(
            dateKey: start.adding(days: i), hasUserContent: score != nil || !m.isEmpty, score: score, moodIDs: m)
    }
}

private func feel(_ this: [DayInput], prev: [DayInput]? = nil) -> WeekFeel? {
    WeekFeel.make(
        from: WeeklyStats.compute(weekStart: week, days: this, workouts: [], previous: prev.map { ($0, []) }))
}

private func makeStore() throws -> JournalStore {
    let container = try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return JournalStore(
        modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
        timeZone: TimeZone(identifier: "UTC")!)
}

@Suite("Week feel")
struct WeekFeelTests {
    @Test("band boundaries: 2.0 difficult, 2.5 mixed, 3.0 okay, 3.5 good, 4.5 great, 4.0 good, 5.0 great")
    func bands() {
        func band(_ scores: [Int]) -> WeekFeel.Band? { feel(days(week, scores: scores))?.band }
        #expect(band([2, 2]) == .difficult)  // 2.0
        #expect(band([2, 3]) == .mixed)  // 2.5
        #expect(band([3, 3]) == .okay)  // 3.0
        #expect(band([3, 4]) == .good)  // 3.5
        #expect(band([4, 4]) == .good)  // 4.0
        #expect(band([4, 5]) == .great)  // 4.5
        #expect(band([5, 5]) == .great)  // 5.0
        #expect(band([1, 1, 1]) == .difficult)
        // 2.33 stays below 2.5, 2.67 is mixed.
        #expect(band([2, 2, 3]) == .difficult)
        #expect(band([2, 3, 3]) == .mixed)
    }

    @Test("top mood is the highest day count; ties go to catalog order")
    func topMood() {
        let f = feel(days(week, moods: [["stressed"], ["happy", "stressed"], ["stressed"]]))
        #expect(f?.topMood == WeekFeel.TopMood(id: "stressed", dayCount: 3))
        // happy and sad tie on two days; happy is first in the catalog even though sad was logged first.
        let tie = feel(days(week, moods: [["sad"], ["sad", "happy"], ["happy"]]))
        #expect(tie?.topMood == WeekFeel.TopMood(id: "happy", dayCount: 2))
        #expect(tie?.band == nil)
    }

    @Test("direction is nil when the comparison is thin, otherwise mapped by tenths of difference")
    func direction() {
        let this = days(week, scores: [4, 4, 4])
        #expect(feel(this)?.direction == nil)
        #expect(feel(this, prev: days(prevWeek, scores: [3, 3]))?.direction == nil)
        #expect(feel(this, prev: days(prevWeek, scores: [4, 4, 4]))?.direction == .similar)  // 0.0
        #expect(feel(this, prev: days(prevWeek, scores: [4, 4, 4, 4, 3]))?.direction == .similar)  // 4.0 vs 3.8 is 0.2
        #expect(feel(this, prev: days(prevWeek, scores: [4, 4, 3]))?.direction == .brighter)  // 4.0 vs 3.7 is 0.3
        #expect(feel(this, prev: days(prevWeek, scores: [3, 3, 3]))?.direction == .brighter)  // +1.0
        #expect(feel(this, prev: days(prevWeek, scores: [5, 5, 5]))?.direction == .harder)  // -1.0
        // 3.0 vs 3.3 is -0.3, harder.
        let flat = days(week, scores: [3, 3, 3])
        #expect(feel(flat, prev: days(prevWeek, scores: [3, 3, 4]))?.direction == .harder)
        #expect(feel(days(week, scores: [3, 3, 4]), prev: days(prevWeek, scores: [3, 3, 3]))?.direction == .brighter)
    }

    @Test("an empty week has no feel; moods alone still give one with no band")
    func emptyWeek() {
        #expect(feel(days(week)) == nil)
        let f = feel(days(week, moods: [["happy"]]))
        #expect(f?.band == nil)
        #expect(f?.topMood == WeekFeel.TopMood(id: "happy", dayCount: 1))
    }

    @Test("smileAnswers is ordered, trimmed and non-blank, within Sunday to Saturday only")
    func smileAnswers() async throws {
        let store = try makeStore()
        _ = try await store.updateEntry(day("2026-10-31"), .smileAnswer("the saturday before"))
        _ = try await store.updateEntry(day("2026-11-07"), .smileAnswer("  saturday walk \n"))
        _ = try await store.updateEntry(day("2026-11-01"), .smileAnswer("sunday coffee"))
        _ = try await store.updateEntry(day("2026-11-03"), .smileAnswer("   "))
        _ = try await store.updateEntry(day("2026-11-04"), .smileAnswer(""))
        _ = try await store.updateEntry(day("2026-11-05"), .score(.good))
        _ = try await store.updateEntry(day("2026-11-08"), .smileAnswer("the next sunday"))

        // Any day in the week resolves to the same Sunday start.
        let answers = try await store.smileAnswers(weekStart: day("2026-11-04"))
        #expect(
            answers == [
                DaySmile(dateKey: day("2026-11-01"), text: "sunday coffee"),
                DaySmile(dateKey: day("2026-11-07"), text: "saturday walk"),
            ])
    }
}
