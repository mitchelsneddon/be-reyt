import Foundation
import Observation
import ReytKit

/// One week's review: the live statistics, the smile answers and the two plans it reads. Everything is recomputed
/// from the records on every content change, and nothing here is written by the review.
@MainActor @Observable
final class ReviewModel {
    let weekStart: DateKey

    private(set) var stats: WeeklyStats?
    private(set) var smiles: [DaySmile] = []
    /// The plan written on the week's first Sunday, with its follow-up. Nil when absent or blank.
    private(set) var followUpPlan: IntentionPlan?
    /// The plan written on the Sunday the review opens, for the coming week. Nil when absent or blank.
    private(set) var nextWeekPlan: IntentionPlan?
    private(set) var isLoaded = false
    private(set) var loadFailed = false

    @ObservationIgnored private let store: JournalStore

    init(weekStart: DateKey, store: JournalStore) {
        self.weekStart = WeekCalendar.reviewWeekStart(containing: weekStart)
        self.store = store
    }

    /// Recomputes everything from the records.
    func refresh() async {
        do {
            let this = try await store.weekInput(weekStart: weekStart)
            let previousStart = WeekCalendar.previousWeekStart(before: weekStart)
            let previous = try await store.weekInput(weekStart: previousStart)
            let computed = WeeklyStats.compute(
                weekStart: weekStart, days: this.days, workouts: this.workouts,
                previous: (previous.days, previous.workouts))
            if computed != stats { stats = computed }
            let smileAnswers = try await store.smileAnswers(weekStart: weekStart)
            if smileAnswers != smiles { smiles = smileAnswers }
            let plans = try await store.intentionPlans()
            let followUp = IntentionQueries.plan(sourcedOn: weekStart, in: plans).flatMap { $0.isBlank ? nil : $0 }
            if followUp != followUpPlan { followUpPlan = followUp }
            let next = IntentionQueries.plan(sourcedOn: WeekCalendar.unlockKey(forWeekStart: weekStart), in: plans)
                .flatMap { $0.isBlank ? nil : $0 }
            if next != nextWeekPlan { nextWeekPlan = next }
            loadFailed = false
            isLoaded = true
        } catch {
            loadFailed = !isLoaded
        }
    }
}
