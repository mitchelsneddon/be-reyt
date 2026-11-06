import Foundation

/// Names inside the picked backup folder, and how a listing is read.
public enum BackupFolderNames {
    public static let root = "be reyt backups"
    public static let snapshots = "snapshots"
    public static let preRestore = "pre-restore"
    public static let blobs = "blobs"

    /// `be-reyt-{YYYY-MM-DD}-{8 hex}.aea`, the day being the app's civil day, not a clock reading.
    public static func snapshotFileName(day: DateKey, token: String = String(UUID().uuidString.prefix(8))) -> String {
        "be-reyt-\(day.string)-\(token.lowercased()).aea"
    }

    /// `be-reyt-pre-restore-{YYYY-MM-DD}-{8 hex}.aea`: the safety copy written before a restore.
    public static func preRestoreFileName(day: DateKey, token: String = String(UUID().uuidString.prefix(8))) -> String {
        "be-reyt-pre-restore-\(day.string)-\(token.lowercased()).aea"
    }

    /// What a snapshot file name says about itself: its civil day and whether it is a pre-restore copy. nil for
    /// any other name (a portable export, a stranger).
    public static func snapshotInfo(fileName: String) -> (day: DateKey, kind: KnownSnapshot.Kind)? {
        guard fileName.hasSuffix(".aea") else { return nil }
        let stem = String(fileName.dropLast(4))
        for (prefix, kind) in [("be-reyt-pre-restore-", KnownSnapshot.Kind.preRestore), ("be-reyt-", .daily)] {
            guard stem.hasPrefix(prefix) else { continue }
            let rest = stem.dropFirst(prefix.count)
            guard rest.count > 11, let day = DateKey(String(rest.prefix(10))), rest.dropFirst(10).first == "-" else {
                continue
            }
            return (day, kind)
        }
        return nil
    }

    /// The real file name a directory entry stands for, or nil when it is not a backup file at all.
    /// iCloud may show an evicted file as a hidden placeholder `.name.icloud`; it may also list it under its real
    /// name (both seen on device). Half-written files (`.partial`) and other hidden files are not backups.
    public static func normalized(_ entryName: String) -> String? {
        if entryName.hasPrefix("."), entryName.hasSuffix(".icloud") {
            let real = String(entryName.dropFirst().dropLast(".icloud".count))
            return real.isEmpty || real.hasPrefix(".") ? nil : real
        }
        if entryName.hasPrefix(".") || entryName.hasSuffix(".partial") { return nil }
        return entryName.hasSuffix(".aea") ? entryName : nil
    }

    /// Prefix of the half-written sibling a file is copied to before being renamed into place.
    public static func partialName(for name: String, token: String = UUID().uuidString) -> String {
        ".\(name).\(token).partial"
    }
}
