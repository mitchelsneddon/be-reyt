import Foundation
import Observation
import ReytKit

/// One day's editable state. Owns the `dateKey` it was opened with, so the page never changes underneath the user.
/// Edits go to `JournalStore` (debounced for text); the store's echo never overwrites the draft.
@MainActor @Observable
final class DayPageModel: DraftFlushing {
    enum SaveState: Equatable { case idle, saving, saved, failed }
    private enum Field: Hashable { case text, smile, rotating, score, moods, intention, followUp }

    let dateKey: DateKey

    private(set) var text = ""
    private(set) var score: DayScore?
    private(set) var moodIDs: [String] = []
    /// The moods the day carried when the page loaded or was last reloaded from outside. The mood grid keeps a
    /// retired mood's tile for this set, so deselecting it during the session does not make it vanish.
    private(set) var loadedMoodIDs: [String] = []
    private(set) var smileAnswer = ""
    private(set) var rotatingAnswer = ""
    /// The persisted assignment for this day; the displayed wording always comes from here.
    private(set) var prompt: PromptChoice?
    /// Rotating prompts are retired: the card shows only on days answered before, so that writing stays visible.
    private(set) var showsRotatingPrompt = false
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    /// Which text fields currently hold focus; the midnight roll treats any of them as "busy".
    enum FocusArea: Hashable { case editor, smile, rotating, followUp, intention }
    private var focusedAreas: Set<FocusArea> = []

    // Sunday plan lifecycle.
    private(set) var intentionText = ""
    private(set) var intentionCategory: String?
    /// The plan whose target week contains this day (shown as "your plan for this week").
    private(set) var coveringPlan: IntentionPlan?
    /// The plan whose follow-up belongs on this day (this day is the Sunday ending its target week).
    private(set) var followUpPlan: IntentionPlan?
    private(set) var followUpNote = ""
    private(set) var followUpSkipped = false
    /// True while the follow-up card is open for writing; a saved note or skip shows collapsed otherwise.
    private(set) var isEditingFollowUp = false

    private var savedText = ""
    private var savedSmile = ""
    private var savedRotating = ""
    private var savedIntention = ""
    private var savedFollowUpNote = ""
    private var inFlight = 0
    /// Bumps when a write is queued and again when it ends, so a reload can tell a write overlapped its fetch.
    private var writeGeneration = 0
    private var failedFields: Set<Field> = []
    private var didSave = false

    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var debounceTasks: [Field: Task<Void, Never>] = [:]
    @ObservationIgnored private let selector = PromptSelector()
    @ObservationIgnored private var chain: Task<Void, Never>?

    init(dateKey: DateKey, store: JournalStore, events: JournalEvents, debounce: Duration = .milliseconds(800)) {
        self.dateKey = dateKey
        self.store = store
        self.events = events
        self.debounce = debounce
        events.register(self)
    }

    // MARK: State

    private var textIsDirty: Bool { text != savedText }
    private var hasUnsavedDrafts: Bool {
        text != savedText || smileAnswer != savedSmile || rotatingAnswer != savedRotating
            || intentionText != savedIntention || followUpNote != savedFollowUpNote
    }

    /// Bumps on every persisted change anywhere; the page reloads its clean fields when it moves.
    var contentRevision: Int { events.contentRevision }

    var isSunday: Bool { dateKey.weekday == 0 }

    /// A saved note or skip shows collapsed with an "edit" affordance.
    var followUpIsCollapsed: Bool {
        !isEditingFollowUp && (followUpSkipped || !followUpNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var saveState: SaveState {
        if !failedFields.isEmpty { return .failed }
        if hasUnsavedDrafts || inFlight > 0 { return .saving }
        return didSave ? .saved : .idle
    }

    /// True when Today may roll to a new day: not focused and nothing waiting to be saved.
    var isIdle: Bool { focusedAreas.isEmpty && !hasUnsavedDrafts && inFlight == 0 }

    // MARK: Loading

    func load() async {
        guard !isLoaded else { return }
        do {
            let snapshot = try await fetchSnapshot()
            apply(snapshot, onlyClean: false)
            showsRotatingPrompt = !rotatingAnswer.isEmpty
            loadFailed = false
            isLoaded = true
            #if DEBUG
                // Simulator-only: `-forceSaveFailure` makes one write fail straight away so the failed state shows.
                if DebugSaveFailure.isRequested { write(.score) }
            #endif
        } catch {
            loadFailed = true
            return
        }
        // No new prompt is assigned; a day answered before gets back its stored one.
        if showsRotatingPrompt { await assignPrompt() }
    }

    /// The store changed (an import, a restore, another screen): refresh every field that has no unsaved local edit
    /// and keep the dirty ones, so the next keystroke can never overwrite what arrived from outside.
    /// A snapshot is applied only if no write of this page was queued, running or finished while it was being
    /// fetched, because such a snapshot may predate that write and would revert it. A skipped snapshot is fetched
    /// once more; if a write still overlaps, that write's own revision bump triggers the next reload.
    func reloadClean() async {
        guard isLoaded else { return }
        for _ in 0..<2 {
            let generation = writeGeneration
            let idleAtStart = inFlight == 0
            guard let snapshot = try? await fetchSnapshot() else { return }
            if idleAtStart, inFlight == 0, generation == writeGeneration {
                apply(snapshot, onlyClean: true)
                return
            }
        }
    }

    private struct Snapshot {
        let content: DayContent
        let plans: [IntentionPlan]
    }

    private func fetchSnapshot() async throws -> Snapshot {
        let content = try await store.dayContent(dateKey)
        let plans = try await store.intentionPlans()
        return Snapshot(content: content, plans: plans)
    }

    /// Applies a snapshot. With `onlyClean`, text fields equal to their saved baseline are refreshed, and the
    /// immediately-written fields (score, moods, categories) only while no write is in flight.
    private func apply(_ snapshot: Snapshot, onlyClean: Bool) {
        let content = snapshot.content
        let plans = snapshot.plans
        let writesIdle = !onlyClean || inFlight == 0
        if !onlyClean || text == savedText {
            text = content.text
            savedText = content.text
        }
        if writesIdle {
            score = content.dayScore.flatMap { DayScore($0) }
            moodIDs = content.moodIDs
            loadedMoodIDs = content.moodIDs
        }
        if !onlyClean || smileAnswer == savedSmile {
            smileAnswer = content.smileAnswer ?? ""
            savedSmile = smileAnswer
        }
        if !onlyClean || rotatingAnswer == savedRotating {
            rotatingAnswer = content.rotatingAnswer ?? ""
            savedRotating = rotatingAnswer
        }
        let own = IntentionQueries.plan(sourcedOn: dateKey, in: plans)
        if !onlyClean || (intentionText == savedIntention && writesIdle) {
            intentionText = own?.text ?? ""
            savedIntention = intentionText
            intentionCategory = own?.category
        }
        let followUp = IntentionQueries.followUpDue(on: dateKey, in: plans)
        followUpPlan = followUp
        if !onlyClean || (followUpNote == savedFollowUpNote && writesIdle) {
            followUpNote = followUp?.followUpNote ?? ""
            savedFollowUpNote = followUpNote
            followUpSkipped = followUp?.followUpSkipped ?? false
        }
        // On the follow-up Sunday itself the follow-up card quotes the plan, so the banner card is not repeated.
        coveringPlan = followUp == nil ? IntentionQueries.planCovering(day: dateKey, in: plans) : nil
    }

    /// First display of a day assigns its prompt; reopening returns the stored one. A failure just hides the card.
    private func assignPrompt() async {
        let selector = selector
        do {
            let result = try await store.assignPromptIfNeeded(dateKey) { key, history in
                selector.select(for: key, history: history)
            }
            events.receive(result.effect)
            prompt = result.choice
        } catch {
            prompt = nil
        }
    }

    // MARK: Edits

    func setFocus(_ area: FocusArea, _ focused: Bool) {
        if focused { focusedAreas.insert(area) } else { focusedAreas.remove(area) }
    }

    func setText(_ newValue: String) {
        guard isLoaded, newValue != text else { return }
        text = newValue
        scheduleWrite(.text)
    }

    func setSmileAnswer(_ newValue: String) {
        guard isLoaded, newValue != smileAnswer else { return }
        smileAnswer = newValue
        scheduleWrite(.smile)
    }

    func setRotatingAnswer(_ newValue: String) {
        guard isLoaded, newValue != rotatingAnswer else { return }
        rotatingAnswer = newValue
        scheduleWrite(.rotating)
    }

    func setIntentionText(_ newValue: String) {
        guard isLoaded, isSunday, newValue != intentionText else { return }
        intentionText = newValue
        scheduleWrite(.intention)
    }

    /// Single-select; tapping the selected category again clears it.
    func toggleIntentionCategory(_ category: String) {
        guard isLoaded, isSunday else { return }
        intentionCategory = intentionCategory == category ? nil : category
        write(.intention)
    }

    func setFollowUpNote(_ newValue: String) {
        guard isLoaded, followUpPlan != nil, newValue != followUpNote else { return }
        followUpNote = newValue
        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { followUpSkipped = false }
        scheduleWrite(.followUp)
    }

    func skipFollowUp() {
        guard isLoaded, followUpPlan != nil else { return }
        debounceTasks[.followUp]?.cancel()
        followUpNote = ""
        savedFollowUpNote = ""
        followUpSkipped = true
        isEditingFollowUp = false
        write(.followUp)
    }

    func editFollowUp() { isEditingFollowUp = true }

    func finishEditingFollowUp() {
        flush()
        isEditingFollowUp = false
    }

    private func scheduleWrite(_ field: Field) {
        debounceTasks[field]?.cancel()
        debounceTasks[field] = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            self?.write(field)
        }
    }

    func setScore(_ newValue: DayScore?) {
        guard isLoaded, newValue != score else { return }
        score = newValue
        write(.score)
    }

    func toggleMood(_ id: String) {
        guard isLoaded else { return }
        moodIDs = MoodCatalog.normalize(moodIDs.contains(id) ? moodIDs.filter { $0 != id } : moodIDs + [id])
        write(.moods)
    }

    // MARK: Saving

    /// Writes any pending text now (scene leaving active, navigating away).
    func flush() {
        for task in debounceTasks.values { task.cancel() }
        debounceTasks = [:]
        if textIsDirty { write(.text) }
        if smileAnswer != savedSmile { write(.smile) }
        if rotatingAnswer != savedRotating { write(.rotating) }
        if intentionText != savedIntention { write(.intention) }
        if followUpNote != savedFollowUpNote { write(.followUp) }
    }

    /// Restore's quiesce step: writes anything pending, then waits for the write chain to drain.
    func flushAndSettle() async {
        flush()
        await chain?.value
    }

    func retry() {
        for field in failedFields { write(field) }
    }

    /// Writes run one after another, each sending the latest local value, so a slow save can never reorder
    /// or revert a newer edit.
    private func write(_ field: Field) {
        inFlight += 1
        writeGeneration += 1
        let previous = chain
        // Captures self strongly on purpose: the chain is bounded (each task ends when its write does), and a weak
        // capture would silently drop queued writes if the model is replaced right after `flush()`.
        chain = Task {
            await previous?.value
            await self.perform(field)
        }
    }

    private func perform(_ field: Field) async {
        defer {
            inFlight -= 1
            writeGeneration += 1
        }
        let change: EntryChange
        var sentText: String?
        var sentSmile: String?
        var sentRotating: String?
        switch field {
        case .text:
            sentText = text
            change = .text(text)
        case .smile:
            sentSmile = smileAnswer
            change = .smileAnswer(smileAnswer)
        case .rotating:
            sentRotating = rotatingAnswer
            change = .rotatingAnswer(rotatingAnswer)
        case .score: change = .score(score)
        case .moods: change = .moods(moodIDs)
        case .intention:
            let sent = intentionText
            do {
                let effect = try await store.saveIntention(sunday: dateKey, text: sent, category: intentionCategory)
                finishWrite(field, effect)
                savedIntention = sent
            } catch {
                failedFields.insert(field)
            }
            return
        case .followUp:
            guard let plan = followUpPlan else { return }
            let sent = followUpNote
            do {
                let effect = try await store.saveFollowUp(
                    sourceSunday: plan.sourceSunday, writtenOn: dateKey, note: sent, skipped: followUpSkipped)
                finishWrite(field, effect)
                savedFollowUpNote = sent
            } catch {
                failedFields.insert(field)
            }
            return
        }
        do {
            #if DEBUG
                if DebugSaveFailure.consume() { throw DebugSaveFailure.Failure() }
            #endif
            let effect = try await store.updateEntry(dateKey, change)
            finishWrite(field, effect)
            if let sentText { savedText = sentText }
            if let sentSmile { savedSmile = sentSmile }
            if let sentRotating { savedRotating = sentRotating }
        } catch {
            // The draft stays in memory; the indicator offers a retry.
            failedFields.insert(field)
        }
    }

    private func finishWrite(_ field: Field, _ effect: StoreEffect) {
        events.receive(effect)
        failedFields.remove(field)
        didSave = true
    }
}
