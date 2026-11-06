import LocalAuthentication
import OSLog
import Observation
import ReytKit

/// Face ID with device-passcode fallback. Locks on cold launch and on every move to the background (no grace
/// period). `.inactive` never locks: the Face ID prompt, pickers and share sheets all cause it.
@MainActor @Observable
final class AppLock {
    private(set) var state: LockState
    /// False until an unlock attempt has been cancelled or has failed in this foregrounding. Until then the lock
    /// screen shows the plain cover (the same as the app-switcher cover), so the unlock button never flashes up
    /// between launch and the Face ID prompt.
    private(set) var offersUnlock = false

    @ObservationIgnored private let isDisabled: Bool
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var attemptID = 0
    @ObservationIgnored private var autoAttempted = false
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "lock")

    init() {
        #if DEBUG
            // Simulator-only: `-skipLock` bypasses the lock (the simulator has no Face ID enrolled by default).
            isDisabled = CommandLine.arguments.contains("-skipLock")
        #else
            isDisabled = false
        #endif
        state = isDisabled ? .unlocked : LockPolicy.launchState
    }

    func didEnterBackground() {
        guard !isDisabled else { return }
        attemptID += 1  // any evaluation still in flight is now stale
        context?.invalidate()
        context = nil
        autoAttempted = false
        offersUnlock = false
        send(.enteredBackground)
    }

    func didBecomeActive() {
        guard !isDisabled, state == .unavailable else { return }
        // the user may have set a passcode while away.
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) { send(.passcodeAvailable) }
    }

    /// Prompts once per foregrounding when the lock screen is showing.
    func authenticateOnceIfNeeded() {
        guard state == .locked, !autoAttempted else { return }
        autoAttempted = true
        Task { await authenticate() }
    }

    func authenticate() async {
        guard !isDisabled, state == .locked else { return }  // never a second evaluation while one is in flight
        send(.authRequested)
        attemptID += 1
        let id = attemptID
        let context = LAContext()
        self.context = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if error?.code == LAError.passcodeNotSet.rawValue {
                send(.passcodeNotSet)
            } else {
                logger.error("cannot evaluate: \(error?.code ?? 0, privacy: .public)")
                offersUnlock = true
                send(.authFailed)
            }
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: Copy.Lock.reason)
            guard id == attemptID else { return }
            if !ok { offersUnlock = true }
            send(ok ? .authSucceeded : .authFailed)
        } catch {
            guard id == attemptID else { return }
            let code = (error as NSError).code
            logger.info("authentication ended: \(code, privacy: .public)")
            // a system or app cancel (the scene went inactive mid-prompt) should be retried on return.
            if code == LAError.systemCancel.rawValue || code == LAError.appCancel.rawValue {
                autoAttempted = false
            } else {
                offersUnlock = true
            }
            send(.authFailed)
        }
    }

    private func send(_ event: LockEvent) { state = LockPolicy.next(state, event) }
}
