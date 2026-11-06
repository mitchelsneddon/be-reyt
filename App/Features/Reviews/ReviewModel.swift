import Foundation
import Observation
import ReytKit

/// One week's review: the live statistics (recomputed on every content change) and the user's own
/// "a little more of next week" answer, autosaved. The store's echo never overwrites the draft.
@MainActor @Observable
final class ReviewModel: DraftFlushing {
    enum SaveState: Equatable { case idle, saving, saved, failed }

    let weekStart: DateKey

    private(set) var stats: WeeklyStats?
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    private(set) var moreOfThisText = ""
    /// Set by the first nonblank save, then fixed; shown as real dates.
    private(set) var targetStart: DateKey?
    private(set) var targetEnd: DateKey?

    private var savedText = ""
    private var inFlight = 0
    private var failed = false
    private var didSave = false
    private var didLoadText = false

    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var chain: Task<Void, Never>?

    init(weekStart: DateKey, store: JournalStore, events: JournalEvents, debounce: Duration = .milliseconds(800)) {
        self.weekStart = WeekCalendar.reviewWeekStart(containing: weekStart)
        self.store = store
        self.events = events
        self.debounce = debounce
        events.register(self)
    }

    var saveState: SaveState {
        if failed { return .failed }
        if moreOfThisText != savedText || inFlight > 0 { return .saving }
        return didSave ? .saved : .idle
    }

    /// Recomputes the statistics from the records. The answer text is read only the first time.
    func refresh() async {
        do {
            let this = try await store.weekInput(weekStart: weekStart)
            let previousStart = WeekCalendar.previousWeekStart(before: weekStart)
            let previous = try await store.weekInput(weekStart: previousStart)
            let computed = WeeklyStats.compute(
                weekStart: weekStart, days: this.days, workouts: this.workouts,
                previous: (previous.days, previous.workouts))
            if computed != stats { stats = computed }
            let more = try await store.moreOfThis(weekStart: weekStart)
            targetStart = more?.targetStart
            targetEnd = more?.targetEnd
            if !didLoadText {
                moreOfThisText = more?.text ?? ""
                savedText = moreOfThisText
                didLoadText = true
            }
            loadFailed = false
            isLoaded = true
        } catch {
            loadFailed = !isLoaded
        }
    }

    func setMoreOfThis(_ newValue: String) {
        guard didLoadText, newValue != moreOfThisText else { return }
        moreOfThisText = newValue
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            self?.write()
        }
    }

    func flush() {
        debounceTask?.cancel()
        debounceTask = nil
        if moreOfThisText != savedText { write() }
    }

    func flushAndSettle() async {
        flush()
        await chain?.value
    }

    func retry() { write() }

    /// Writes run one after another, each sending the latest local value, so a slow save never reverts a newer edit.
    private func write() {
        inFlight += 1
        let previous = chain
        // Captures self strongly on purpose: the chain is bounded (each task ends when its write does), and a weak
        // capture would silently drop queued writes if the model is replaced right after `flush()`.
        chain = Task {
            await previous?.value
            await self.perform()
        }
    }

    private func perform() async {
        defer { inFlight -= 1 }
        let sent = moreOfThisText
        do {
            let effect = try await store.saveMoreOfThis(weekStart: weekStart, text: sent, savedOn: AppClock.today())
            events.receive(effect)
            savedText = sent
            failed = false
            didSave = true
            if let more = try? await store.moreOfThis(weekStart: weekStart) {
                targetStart = more.targetStart
                targetEnd = more.targetEnd
            }
        } catch {
            failed = true
        }
    }
}
