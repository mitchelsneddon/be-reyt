import Foundation
import Observation
import ReytKit

/// The reviews tab's list: every eligible week (newest first) with how many of its days were recorded. Creates
/// the persisted row for each week it sees as newly eligible; generates nothing.
@MainActor @Observable
final class ReviewsListModel {
    struct Row: Identifiable, Equatable {
        let weekStart: DateKey
        let recordedDays: Int
        /// The week's seven day scores, Sunday to Saturday; nil where a day has no score.
        let scores: [DayScore?]
        var id: DateKey { weekStart }
    }

    private(set) var rows: [Row] = []
    private(set) var isLoaded = false
    private(set) var loadFailed = false

    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents

    init(store: JournalStore, events: JournalEvents) {
        self.store = store
        self.events = events
    }

    /// The latest eligible week is the first row; it is the "this week's review" one.
    var latestWeek: DateKey? { rows.first?.weekStart }

    func refresh(today: DateKey) async {
        do {
            // One pass over the days with content gives both the earliest day and every week's coverage.
            let days = try await store.historyDays()
            var perWeek: [DateKey: Int] = [:]
            var scoresByDay: [DateKey: DayScore] = [:]
            for day in days {
                perWeek[WeekCalendar.reviewWeekStart(containing: day.dateKey), default: 0] += 1
                if let raw = day.content.dayScore, let score = DayScore(rawValue: raw) {
                    scoresByDay[day.dateKey] = score
                }
            }
            let persisted = try await store.reviewRows()
            let eligibility = ReviewEligibility(
                today: today, earliestContentDay: days.last?.dateKey, persisted: persisted)
            let newly = eligibility.newlyEligible()
            if !newly.isEmpty {
                let effect = try await store.ensureReviewRows(
                    for: newly, unlockedAt: AppClock.now(), timeZoneID: TimeZone.current.identifier)
                events.receive(effect)
            }
            let listed = eligibility.listedWeeks().map { start in
                Row(
                    weekStart: start, recordedDays: perWeek[start] ?? 0,
                    scores: (0..<7).map { scoresByDay[start.adding(days: $0)] })
            }
            if listed != rows { rows = listed }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoaded = true
    }
}
