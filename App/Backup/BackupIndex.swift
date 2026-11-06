import Foundation
import ReytKit

/// Why the last run did not finish. Stored as a code (never a message), turned into calm copy by the UI.
enum BackupErrorCode: String, Codable, Equatable, Sendable {
    case folderMissing, storageFull, uploadFailed, photoUnreadable, verifyFailed, other
}

/// The app's own record of the backup set, device-local and never archived. Reconciled with the folder listing
/// before every decision, so a file the user deleted in Files, or one iCloud evicted, is read correctly.
struct BackupIndex: Codable, Equatable, Sendable {
    /// Issued at the first backup and re-issued at every restore. One snapshot per day per lineage.
    var lineageID = UUID()
    var snapshots: [KnownSnapshot] = []
    /// Blob name to its encrypted size, for blobs this device wrote and verified.
    var knownBlobs: [String: Int] = [:]
    var lastSnapshotName: String?
    /// When the latest snapshot was verified in the folder.
    var lastSnapshotWrittenAt: Date?
    /// The snapshot time iCloud was last seen to have fully uploaded (snapshot and the blobs written with it).
    var lastUploadConfirmedAt: Date?
    /// Blobs written by the latest run, whose upload the status also waits for.
    var latestRunBlobs: [String] = []
    var pendingChanges = false
    var lastError: BackupErrorCode?
    var cleanupPaused = false

    // MARK: Persistence

    static func url(in paths: Paths) -> URL {
        paths.deviceRoot.appending(path: "backup-index.json", directoryHint: .notDirectory)
    }

    static func load(from paths: Paths) -> BackupIndex {
        guard let data = try? Data(contentsOf: url(in: paths)),
            let index = try? decoder.decode(BackupIndex.self, from: data)
        else { return BackupIndex() }
        return index
    }

    func save(to paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.deviceRoot, withIntermediateDirectories: true)
        let file = Self.url(in: paths)
        try Self.encoder.encode(self).write(to: file, options: [.atomic, .completeFileProtection])
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Reconcile

    /// Drops what the folder no longer has. Never adds anything: a listed file the index doesn't know stays a
    /// stranger, which is exactly what makes `BackupPlan` pause cleanup.
    mutating func reconcile(with items: [DestinationItem]) {
        let snapshotNames = Set(items.filter { $0.area != .blobs }.map(\.name))
        let blobNames = Set(items.filter { $0.area == .blobs }.compactMap { BlobNaming.name(fromFileName: $0.name) })
        snapshots.removeAll { !snapshotNames.contains($0.name) }
        knownBlobs = knownBlobs.filter { blobNames.contains($0.key) }
        if let last = lastSnapshotName, !snapshotNames.contains(last) { lastSnapshotName = nil }
    }

    /// The listed blob names, whoever wrote them.
    static func blobNames(in items: [DestinationItem]) -> Set<String> {
        Set(items.filter { $0.area == .blobs }.compactMap { BlobNaming.name(fromFileName: $0.name) })
    }

    static func snapshotNames(in items: [DestinationItem]) -> Set<String> {
        Set(items.filter { $0.area != .blobs }.map(\.name))
    }
}
