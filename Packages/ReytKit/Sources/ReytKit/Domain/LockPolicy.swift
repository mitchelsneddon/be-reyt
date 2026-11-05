import Foundation

/// Where the app lock is. Pure state, no platform types, so the rules are testable without Face ID.
public enum LockState: Sendable, Equatable {
    case locked
    case authenticating
    case unlocked
    /// No device passcode is set, so there is nothing to lock with. The app stays usable, with a warning.
    case unavailable
}

public enum LockEvent: Sendable, Equatable {
    case coldLaunch
    /// `scenePhase == .background`. Locks immediately, no grace period.
    case enteredBackground
    /// `scenePhase == .inactive`: Face ID prompt, pickers, share sheet, control centre. Never locks.
    case enteredInactive
    case authRequested
    case authSucceeded
    /// The user cancelled, authentication failed, or the system cancelled it.
    case authFailed
    case passcodeNotSet
    case passcodeAvailable
}

public enum LockPolicy {
    public static let launchState: LockState = .locked

    public static func next(_ state: LockState, _ event: LockEvent) -> LockState {
        switch (state, event) {
        case (_, .coldLaunch):
            .locked
        case (.unavailable, .enteredBackground):
            .unavailable
        case (_, .enteredBackground):
            .locked
        case (.locked, .authRequested):
            .authenticating
        case (.authenticating, .authSucceeded):
            .unlocked
        case (.authenticating, .authFailed):
            .locked
        case (.authenticating, .passcodeNotSet):
            .unavailable
        case (.unavailable, .passcodeAvailable):
            .locked
        default:
            // includes `.enteredInactive`, a second request while one is in flight, and stale results.
            state
        }
    }
}
