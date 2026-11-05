import Foundation
import OSLog

/// Everything device-local that "delete all data" must clear besides the journal itself: the Keychain passphrase,
/// the Health anchor, pending reminders, files under `Device/`.
///
/// Owners register one wiper each, at launch, in `BeReytApp.init`. Any NEW device-local state added later (the
/// automatic backup's data key, backup index and folder bookmark, for example) must register its own wiper here,
/// or delete-all will leave it behind. A wiper throws if it could not finish; the failure is reported by `name`
/// and does not stop the others.
@MainActor
final class DeviceDataRegistry {
    typealias Wiper = @Sendable () async throws -> Void

    private struct Entry {
        let name: String
        let wipe: Wiper
    }

    private var entries: [Entry] = []
    private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "delete-all")

    /// `name` is lowercase plain words, shown to the person if the wiper fails.
    func register(_ name: String, _ wiper: @escaping Wiper) {
        entries.append(Entry(name: name, wipe: wiper))
    }

    /// Runs every wiper and returns the names of those that failed.
    func wipeAll() async -> [String] {
        var failed: [String] = []
        for entry in entries {
            do {
                try await entry.wipe()
            } catch {
                logger.error("wiper failed: \(String(describing: type(of: error)), privacy: .public)")
                failed.append(entry.name)
            }
        }
        return failed
    }
}
