import Foundation
import ReytKit

/// Decides whether first-run onboarding shows. The flag is device-local (`UserDefaults`), cleared by delete-all.
enum OnboardingGate {
    static let key = "onboarding.completed.v1"

    static func isCompleted() -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func markCompleted() { UserDefaults.standard.set(true, forKey: key) }
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    /// Existing content latches the flag (so clearing every entry later never shows onboarding). Otherwise it
    /// shows only while the flag is unset.
    static func shouldShow(earliestContentDay: DateKey?) -> Bool {
        #if DEBUG
            // Simulator-only: `-showOnboarding` forces it, `-skipOnboarding` suppresses it (writes nothing).
            if CommandLine.arguments.contains("-showOnboarding") { return true }
            if CommandLine.arguments.contains("-skipOnboarding") { return false }
        #endif
        if earliestContentDay != nil {
            markCompleted()
            return false
        }
        return !isCompleted()
    }
}
