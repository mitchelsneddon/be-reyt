import LocalAuthentication
import OSLog

/// A fresh Face ID or passcode check before something destructive or sensitive (restore, changing the backup
/// passphrase). Separate from `AppLock`, which owns the lock screen state: this never changes it. The system
/// prompt only makes the scene inactive, so it can't trigger a relock.
enum Reauthenticator {
    private static let logger = Logger(subsystem: "local.mitchel.bereyt", category: "reauth")

    @MainActor
    static func confirm(reason: String) async -> Bool {
        #if DEBUG
            // Simulator-only, like `-skipLock`.
            if CommandLine.arguments.contains("-skipLock") { return true }
        #endif
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on the phone: the app already runs unlocked with a warning, so there is nothing to ask.
            return error?.code == LAError.passcodeNotSet.rawValue
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            logger.info("reauth ended: \((error as NSError).code, privacy: .public)")
            return false
        }
    }
}
