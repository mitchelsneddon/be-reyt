import Foundation
import Observation
import ReytKit

enum ReflectionState: Equatable {
    case loading
    case notGenerated
    case generating
    case ready(WeeklyReflectionContent, newerPromptAvailable: Bool)
    case unavailable(ReflectionFailure)
    case failed(ReflectionFailure)
    /// A narrative existed and was cleared because the week changed.
    case purged
}

/// The reflection for one week. A narrative is only ever shown after the store re-checked its fingerprint, and
/// only from the persisted row (A2); generation is always started by the reader, never automatically.
@MainActor @Observable
final class ReflectionModel {
    private(set) var state: ReflectionState = .loading

    @ObservationIgnored private let weekStart: DateKey
    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let generator: any ReflectionGenerating

    init(
        weekStart: DateKey, store: JournalStore, events: JournalEvents,
        generator: any ReflectionGenerating = OnDeviceReflectionGenerator()
    ) {
        self.weekStart = weekStart
        self.store = store
        self.events = events
        self.generator = generator
    }

    var isGenerating: Bool { state == .generating }

    /// Reads the persisted state. Never interrupts a running generation.
    func load() async {
        if state == .generating { return }
        do {
            let valid = try await store.validateNarrative(weekStart: weekStart)
            let stored = try await store.storedNarrative(weekStart: weekStart)
            if valid, let content = stored?.content {
                let newer = (stored?.promptVersion ?? 0) < ReflectionPrompt.promptVersion
                state = .ready(content, newerPromptAvailable: newer)
                return
            }
            switch state {
            case .failed, .unavailable:
                return
            default:
                break
            }
            if stored?.purgeReason != nil {
                state = .purged
            } else if let reason = await generator.unavailability() {
                state = .unavailable(reason)
            } else {
                state = .notGenerated
            }
        } catch {
            if state == .loading { state = .failed(.couldNotSave) }
        }
    }

    /// Clears a shown failure and re-reads (the "try again" for unavailable states).
    func recheck() async {
        if case .unavailable = state { state = .loading }
        await load()
    }

    func generate() async {
        guard state != .generating else { return }
        state = .generating
        let coordinator = ReflectionCoordinator(
            store: store, generator: generator, promptVersion: ReflectionPrompt.promptVersion,
            osBuild: OnDeviceReflectionGenerator.osBuild)
        #if DEBUG
            let started = ContinuousClock.now
        #endif
        // Its own task: the caller is often a SwiftUI `.task(id:)` that is cancelled whenever the journal's
        // revision changes, and that cancellation must not reach the on-device model mid-write.
        let outcome = await Task { await coordinator.run(weekStart: weekStart) }.value
        #if DEBUG
            ReflectionLog.note("run finished \(outcome.logLabel) after \(ContinuousClock.now - started)")
        #endif
        switch outcome {
        case .saved:
            events.receive(StoreEffect(dirty: true))
            state = .loading
            await load()
        case .failed(let failure):
            state = failure.isUnavailability ? .unavailable(failure) : .failed(failure)
            if failure == .changedWhileWriting { events.receive(StoreEffect()) }
        }
    }
}

#if DEBUG
    extension ReflectionCoordinator.Outcome {
        fileprivate var logLabel: String {
            switch self {
            case .saved: "saved"
            case .failed(let f): "failed(\(f))"
            }
        }
    }
#endif
