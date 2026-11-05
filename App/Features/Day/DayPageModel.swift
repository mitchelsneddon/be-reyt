import Foundation
import Observation
import ReytKit

/// One day's editable state. Owns the `dateKey` it was opened with, so the page never changes underneath the user.
/// Edits go to `JournalStore` (debounced for text); the store's echo never overwrites the draft.
@MainActor @Observable
final class DayPageModel {
    enum SaveState: Equatable { case idle, saving, saved, failed }
    enum AddTagResult { case added, blank, failed }
    private enum Field: Hashable { case text, score, moods, tags }

    let dateKey: DateKey

    private(set) var text = ""
    private(set) var score: DayScore?
    private(set) var moodIDs: [String] = []
    private(set) var tagIDs: [UUID] = []
    private(set) var isLoaded = false
    private(set) var loadFailed = false
    var isEditorFocused = false

    private var savedText = ""
    private var inFlight = 0
    private var failedFields: Set<Field> = []
    private var didSave = false

    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var chain: Task<Void, Never>?

    init(dateKey: DateKey, store: JournalStore, events: JournalEvents, debounce: Duration = .milliseconds(800)) {
        self.dateKey = dateKey
        self.store = store
        self.events = events
        self.debounce = debounce
    }

    // MARK: State

    private var textIsDirty: Bool { text != savedText }

    var saveState: SaveState {
        if !failedFields.isEmpty { return .failed }
        if textIsDirty || inFlight > 0 { return .saving }
        return didSave ? .saved : .idle
    }

    /// True when Today may roll to a new day: not focused and nothing waiting to be saved.
    var isIdle: Bool { !isEditorFocused && !textIsDirty && inFlight == 0 }

    // MARK: Loading

    func load() async {
        guard !isLoaded else { return }
        do {
            let content = try await store.dayContent(dateKey)
            text = content.text
            savedText = content.text
            score = content.dayScore.flatMap { DayScore($0) }
            moodIDs = content.moodIDs
            tagIDs = content.tagIDs
            loadFailed = false
            isLoaded = true
        } catch {
            loadFailed = true
        }
    }

    // MARK: Edits

    func setText(_ newValue: String) {
        guard isLoaded, newValue != text else { return }
        text = newValue
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            self?.write(.text)
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

    func toggleTag(_ id: UUID) {
        guard isLoaded else { return }
        if tagIDs.contains(id) { tagIDs.removeAll { $0 == id } } else { tagIDs.append(id) }
        write(.tags)
    }

    func addTag(named name: String) async -> AddTagResult {
        guard isLoaded else { return .failed }
        do {
            let created = try await store.createTag(name: name)
            events.receive(created.effect)
            if !tagIDs.contains(created.id) {
                tagIDs.append(created.id)
                write(.tags)
            }
            return .added
        } catch JournalStoreError.invalidTagName {
            return .blank
        } catch {
            return .failed
        }
    }

    // MARK: Saving

    /// Writes any pending text now (scene leaving active, navigating away).
    func flush() {
        debounceTask?.cancel()
        if textIsDirty { write(.text) }
    }

    func retry() {
        for field in failedFields { write(field) }
    }

    /// Writes run one after another, each sending the latest local value, so a slow save can never reorder
    /// or revert a newer edit.
    private func write(_ field: Field) {
        inFlight += 1
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            await self?.perform(field)
        }
    }

    private func perform(_ field: Field) async {
        defer { inFlight -= 1 }
        let change: EntryChange
        var sentText: String?
        switch field {
        case .text:
            sentText = text
            change = .text(text)
        case .score: change = .score(score)
        case .moods: change = .moods(moodIDs)
        case .tags: change = .tags(tagIDs)
        }
        do {
            let effect = try await store.updateEntry(dateKey, change)
            events.receive(effect)
            failedFields.remove(field)
            didSave = true
            if let sentText { savedText = sentText }
        } catch {
            // The draft stays in memory; the indicator offers a retry.
            failedFields.insert(field)
        }
    }
}
