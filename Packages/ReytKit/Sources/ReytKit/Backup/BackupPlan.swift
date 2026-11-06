import Foundation

/// One snapshot the app knows about (from its own index, reconciled with the folder listing).
public struct KnownSnapshot: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case daily, preRestore }

    public var name: String
    public var dayKey: DateKey
    public var lineageID: UUID
    public var kind: Kind
    /// Written, re-read, decrypted and validated, with every referenced blob confirmed present.
    public var verified: Bool
    public var createdAt: Date
    /// nil when this device does not know what the snapshot references (written elsewhere or under another passphrase).
    public var referencedBlobNames: Set<String>?

    public init(
        name: String, dayKey: DateKey, lineageID: UUID, kind: Kind = .daily, verified: Bool, createdAt: Date,
        referencedBlobNames: Set<String>?
    ) {
        self.name = name
        self.dayKey = dayKey
        self.lineageID = lineageID
        self.kind = kind
        self.verified = verified
        self.createdAt = createdAt
        self.referencedBlobNames = referencedBlobNames
    }
}

/// The data-loss-critical decisions of the automatic backup, as pure functions: when a snapshot is due, which one
/// it replaces, and, only after a new snapshot verified, what may be deleted. Nothing here touches the disk.
public enum BackupPlan {
    public static let retention = 30
    public static let preRestoreExemptionDays = 30
    /// A same-day snapshot is refreshed at most this often.
    public static let refreshInterval: TimeInterval = 5 * 60

    // MARK: Due and replace

    /// A snapshot is due when something changed and either today (in this lineage) has no verified snapshot yet, or
    /// the one it has is older than the refresh interval.
    public static func isDue(
        dirty: Bool, today: DateKey, lineageID: UUID, snapshots: [KnownSnapshot], now: Date,
        refreshInterval: TimeInterval = BackupPlan.refreshInterval
    ) -> Bool {
        guard dirty else { return false }
        guard let latest = sameDay(today, lineageID, snapshots).map(\.createdAt).max() else { return true }
        return now.timeIntervalSince(latest) >= refreshInterval
    }

    /// The only snapshots a new one may replace: today's verified daily snapshots of the same lineage.
    /// A different lineage's snapshot of the same day (before a restore) is never a target.
    public static func replacementTargets(
        today: DateKey, lineageID: UUID, snapshots: [KnownSnapshot]
    ) -> [String] {
        sameDay(today, lineageID, snapshots).map(\.name).sorted()
    }

    private static func sameDay(_ day: DateKey, _ lineageID: UUID, _ snapshots: [KnownSnapshot]) -> [KnownSnapshot] {
        snapshots.filter { $0.kind == .daily && $0.verified && $0.dayKey == day && $0.lineageID == lineageID }
    }

    // MARK: Cleanup

    public struct Cleanup: Equatable, Sendable {
        /// Snapshot names to delete: replaced same-day snapshots, dailies past retention, expired pre-restore copies.
        public var snapshotsToDelete: [String] = []
        /// Blob names to delete: referenced by no kept snapshot. Empty whenever `cleanupPaused`.
        public var blobsToDelete: [String] = []
        /// A kept snapshot's references are unknown, so no blob may be deleted.
        public var cleanupPaused = false
        public var kept: [String] = []
        public init() {}
    }

    /// What to delete after `newSnapshot` was written and verified. `snapshots` is the index (it includes the new
    /// snapshot); `folderSnapshotNames` and `folderBlobNames` are what the folder listing shows right now.
    /// A listed snapshot the index does not know is kept and has unknown references, which pauses blob cleanup.
    /// A run that did not verify deletes nothing.
    public static func cleanup(
        runVerified: Bool, newSnapshot: String, snapshots: [KnownSnapshot], folderSnapshotNames: Set<String>,
        folderBlobNames: Set<String>, now: Date, retention: Int = BackupPlan.retention,
        preRestoreExemptionDays: Int = BackupPlan.preRestoreExemptionDays
    ) -> Cleanup {
        var result = Cleanup()
        guard runVerified,
            let new = snapshots.first(where: { $0.name == newSnapshot && $0.verified }),
            folderSnapshotNames.contains(newSnapshot)
        else { return result }

        // Only what is really in the folder counts. An index entry whose file is gone is no restore point.
        let present = snapshots.filter { folderSnapshotNames.contains($0.name) && $0.verified }
        let replaced = Set(
            present.filter {
                $0.name != new.name && $0.kind == .daily && $0.dayKey == new.dayKey && $0.lineageID == new.lineageID
            }.map(\.name))

        let expiry = now.addingTimeInterval(-Double(preRestoreExemptionDays) * 86_400)
        let dailies = present.filter { $0.kind == .daily && !replaced.contains($0.name) }
            .sorted { ($0.createdAt, $0.name) > ($1.createdAt, $1.name) }
        let keptDailies = Array(dailies.prefix(max(retention, 1)))
        let prunedDailies = dailies.dropFirst(max(retention, 1))
        let preRestore = present.filter { $0.kind == .preRestore }
        let keptPreRestore = preRestore.filter { $0.createdAt > expiry }
        let expiredPreRestore = preRestore.filter { $0.createdAt <= expiry }

        result.snapshotsToDelete =
            (replaced.sorted() + prunedDailies.map(\.name) + expiredPreRestore.map(\.name))
        let kept = keptDailies + keptPreRestore
        result.kept = kept.map(\.name).sorted()

        // Blob cleanup needs to know what every kept snapshot needs: the ones in the index, and every listed
        // snapshot the index has never seen (another device, an older passphrase, an empty index after reinstall).
        let known = Set(snapshots.map(\.name))
        let strangers = folderSnapshotNames.subtracting(known)
        if kept.contains(where: { $0.referencedBlobNames == nil }) || !strangers.isEmpty {
            result.cleanupPaused = true
            return result
        }
        let referenced = kept.reduce(into: Set<String>()) { $0.formUnion($1.referencedBlobNames ?? []) }
        result.blobsToDelete = folderBlobNames.subtracting(referenced).sorted()
        return result
    }
}
