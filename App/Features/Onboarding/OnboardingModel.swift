import Observation
import ReytKit

/// Owned by `BeReytApp`, above the lock switch and `.id(generation)`, so the step survives relock and restore.
@MainActor @Observable
final class OnboardingModel {
    enum Step { case reminder, workouts, backups }

    var step: Step = .reminder
    var isPresented = false
    private var evaluated = false

    init() {
        #if DEBUG
            // Simulator-only: `-onboardingStep 1|2|3` opens at that step (use with `-showOnboarding`).
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-onboardingStep"), args.indices.contains(i + 1) {
                switch args[i + 1] {
                case "2": step = .workouts
                case "3": step = .backups
                default: break
                }
            }
        #endif
    }

    /// Once per process, after the first unlock. A failed read decides nothing, so a later unlock may retry.
    func evaluate(store: JournalStore) async {
        guard !evaluated else { return }
        do {
            decide(earliestContentDay: try await store.earliestContentDay())
        } catch {
            // Unknown is not empty: show nothing this time rather than greet an existing journal.
        }
    }

    func advance() {
        switch step {
        case .reminder: step = .workouts
        case .workouts: step = .backups
        case .backups: finish()
        }
    }

    func skipStep() { advance() }

    func finish() {
        OnboardingGate.markCompleted()
        isPresented = false
    }

    private func decide(earliestContentDay: DateKey?) {
        evaluated = true
        isPresented = OnboardingGate.shouldShow(earliestContentDay: earliestContentDay)
    }
}
