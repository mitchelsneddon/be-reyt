import Foundation
import HealthKit

/// Device-local persistence of the HealthKit anchor that marks "everything up to here is already synced".
/// Lives under `Paths.deviceRoot`, outside the journal schema, so a backup never carries it: after a restore the
/// workouts come back from Health, not from the archive.
struct HealthAnchorStore: Sendable {
    let url: URL

    init(deviceRoot: URL) {
        url = deviceRoot.appending(path: "health-anchor.bin", directoryHint: .notDirectory)
    }

    /// A missing or unreadable file is "no anchor", which makes the next sync a full one. Safe because upserts are
    /// idempotent.
    func load() -> HKQueryAnchor? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func save(_ anchor: HKQueryAnchor) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
