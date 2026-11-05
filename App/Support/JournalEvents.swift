import Observation
import ReytKit

/// Receives every `StoreEffect` from the feature models. Today it only records that the backup is stale;
/// BackupManager (later) reads `isDirty`, and ReminderScheduler plugs in through `onContentChange`.
@MainActor @Observable
final class JournalEvents {
    private(set) var isDirty = false
    /// Bumped on every persisted change, so history can refresh its dots, list and search.
    private(set) var contentRevision = 0

    /// Hook for reminders: called with the days whose `hasUserContent` flipped. No-op until S10.
    @ObservationIgnored var onContentChange: (Set<DateKey>) -> Void = { _ in }

    func receive(_ effect: StoreEffect) {
        guard !effect.isEmpty else { return }
        if effect.dirty {
            isDirty = true
            contentRevision += 1
        }
        if !effect.contentChangedDays.isEmpty { onContentChange(effect.contentChangedDays) }
    }
}
