import Foundation

/// Why a reflection could not be written. The app maps each case to calm copy; none carries journal text.
public enum ReflectionFailure: Error, Equatable, Sendable {
    // The model is not usable right now.
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLanguage
    // The model was used and did not deliver.
    case guardrail
    case refused
    case tooLong
    case timedOut
    case rateLimited
    case busy
    case unreadableAnswer
    case invalidAnswer
    case modelError
    // Around the model.
    /// The task running the attempt was cancelled (a view re-appearing, the app leaving). Retryable, not a model fault.
    case cancelled
    case changedWhileWriting
    case couldNotSave
    case noEntries

    /// True for the reasons that mean "the on-device model is not available", shown as unavailable not failed.
    public var isUnavailability: Bool {
        switch self {
        case .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unsupportedLanguage: true
        default: false
        }
    }
}

/// The model side of a reflection. The real one talks to Apple's on-device model only; tests use a fake.
public protocol ReflectionGenerating: Sendable {
    /// nil when the model can be used now.
    func unavailability() async -> ReflectionFailure?
    /// One attempt at the whole narrative. `retryReasons` is empty on the first attempt and lists what the
    /// validator rejected on the second. Throws `ReflectionFailure` for anything the model side can hit.
    func generate(input: ReflectionInput, facts: WeeklyStats, retryReasons: [String]) async throws
        -> WeeklyReflectionContent
}

/// Reads the week, asks the generator, validates, and saves only if the week did not change meanwhile.
/// Never generates for a week with nothing recorded, and never calls any model but the one it is given.
public struct ReflectionCoordinator: Sendable {
    public enum Outcome: Equatable, Sendable {
        case saved(WeeklyReflectionContent)
        case failed(ReflectionFailure)
    }

    private let store: JournalStore
    private let generator: any ReflectionGenerating
    private let promptVersion: Int
    private let osBuild: String

    public init(store: JournalStore, generator: any ReflectionGenerating, promptVersion: Int, osBuild: String) {
        self.store = store
        self.generator = generator
        self.promptVersion = promptVersion
        self.osBuild = osBuild
    }

    public func run(weekStart rawWeek: DateKey) async -> Outcome {
        let week = WeekCalendar.reviewWeekStart(containing: rawWeek)
        do {
            let week7 = try await store.weekInput(weekStart: week)
            let input = try await store.reflectionInput(weekStart: week)
            let facts = WeeklyStats.compute(weekStart: week, days: week7.days, workouts: week7.workouts)
            if facts.recordedDays == 0 || input.days.isEmpty { return .failed(.noEntries) }
            if let reason = await generator.unavailability() { return .failed(reason) }
            let fingerprint = try ReviewFingerprint.compute(input)

            var content: WeeklyReflectionContent?
            var reasons: [String] = []
            for _ in 0..<2 {
                let raw = try await generator.generate(input: input, facts: facts, retryReasons: reasons)
                let candidate = ReflectionSanitiser.sanitise(raw, against: input)
                switch ReflectionValidator.validate(candidate, against: input) {
                case .valid(let ok):
                    content = ok
                case .invalid(let why):
                    reasons = why
                }
                if content != nil { break }
            }
            guard let content else { return .failed(.invalidAnswer) }

            let now = try ReviewFingerprint.compute(try await store.reflectionInput(weekStart: week))
            guard now == fingerprint else { return .failed(.changedWhileWriting) }
            _ = try await store.saveNarrative(
                weekStart: week, content: content, fingerprint: fingerprint, promptVersion: promptVersion,
                osBuild: osBuild)
            return .saved(content)
        } catch let failure as ReflectionFailure {
            return .failed(failure)
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch JournalStoreError.fingerprintMismatch {
            return .failed(.changedWhileWriting)
        } catch {
            return .failed(.couldNotSave)
        }
    }
}
