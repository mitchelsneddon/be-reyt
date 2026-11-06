import Observation
import ReytKit

/// A model holding unsaved edits. Restore asks every live one to write and settle before the store goes read-only.
@MainActor protocol DraftFlushing: AnyObject {
    func flushAndSettle() async
}

/// Receives every `StoreEffect` from the feature models. Today it only records that the backup is stale;
/// BackupManager (later) reads `isDirty`, and ReminderScheduler plugs in through `onContentChange`.
@MainActor @Observable
final class JournalEvents {
    private(set) var isDirty = false
    /// Bumped on every persisted change, so history can refresh its dots, list and search.
    private(set) var contentRevision = 0

    /// Hook for reminders: called with the days whose `hasUserContent` flipped.
    @ObservationIgnored var onContentChange: (Set<DateKey>) -> Void = { _ in }

    /// Hook for the automatic backup: called on every persisted change.
    @ObservationIgnored var onDirty: @MainActor () -> Void = {}

    @ObservationIgnored private var flushers: [WeakFlusher] = []

    private struct WeakFlusher {
        weak var value: DraftFlushing?
    }

    func register(_ flusher: DraftFlushing) {
        flushers.removeAll { $0.value == nil }
        flushers.append(WeakFlusher(value: flusher))
    }

    /// Writes every pending draft and waits for in-flight writes to finish.
    func flushAllDrafts() async {
        for flusher in flushers.compactMap(\.value) { await flusher.flushAndSettle() }
    }

    func receive(_ effect: StoreEffect) {
        guard !effect.isEmpty else { return }
        if effect.dirty {
            isDirty = true
            contentRevision += 1
            onDirty()
        }
        if !effect.contentChangedDays.isEmpty { onContentChange(effect.contentChangedDays) }
    }
}
