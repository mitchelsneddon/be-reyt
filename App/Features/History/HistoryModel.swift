import Foundation
import Observation
import ReytKit

/// What the history tab shows: every day with content (for the calendar dots and the list) and the days matching
/// the current search. Reads only; the store owns the content definition (A3) and the matching.
@MainActor @Observable
final class HistoryModel {
    private(set) var days: [DaySummary] = []
    private(set) var results: [DaySummary] = []
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    var searchText = ""
    var tagIDs: Set<UUID> = []

    @ObservationIgnored private let store: JournalStore

    init(store: JournalStore) { self.store = store }

    var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tagIDs.isEmpty
    }

    /// Drops filter tags that no longer exist (a tag was deleted), so the list can never be stuck on a hidden filter.
    func pruneTags(existing: Set<UUID>) {
        let kept = tagIDs.intersection(existing)
        if kept != tagIDs { tagIDs = kept }
    }

    /// Days with content mapped to their score (nil when unscored), for the calendar's coloured dots.
    var dayScores: [DateKey: DayScore?] {
        Dictionary(
            uniqueKeysWithValues: days.map { ($0.dateKey, $0.content.dayScore.flatMap { DayScore(rawValue: $0) }) })
    }

    /// Reloads the days, then the search results when a search is active.
    func refresh() async {
        do {
            days = try await store.historyDays()
            loadFailed = false
            if isFiltering {
                let keys = try await store.searchDays(text: searchText, tagIDs: tagIDs)
                let byKey = Dictionary(uniqueKeysWithValues: days.map { ($0.dateKey, $0) })
                results = keys.compactMap { byKey[$0] }
            } else {
                results = []
            }
        } catch {
            loadFailed = true
        }
        isLoaded = true
    }
}
