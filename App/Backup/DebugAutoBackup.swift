#if DEBUG
    import Foundation
    import OSLog
    import ReytKit

    /// Simulator-only drivers for the automatic backup: `-backupFolder <path>` (a plain folder instead of the
    /// picker, set up in `BackupManager`), `-backupEditToday <text>`, `-backupNow`, `-dumpBackupIndex`
    /// (`Documents/backup-index-dump.json`). Results (names, counts, outcomes, never journal text) go to the log
    /// and to `Documents/backup-auto-debug.txt`.
    enum DebugAutoBackup {
        private static let logger = Logger(subsystem: "local.mitchel.bereyt", category: "debug-auto-backup")

        private static func value(after flag: String) -> String? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }

        @MainActor
        static func runIfRequested(manager: BackupManager, host: ContainerHost, backup: BackupSettingsModel) async {
            let args = CommandLine.arguments
            guard args.contains("-backupNow") || args.contains("-dumpBackupIndex") || args.contains("-backupEditToday")
            else { return }
            if let passphrase = value(after: "-debugPassphrase") {
                PassphraseStore.debugOverride = passphrase
                backup.refresh()
            }
            var waited = 0
            while host.store == nil || !manager.isActive, waited < 400 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            guard let store = host.store else { return log("store never opened") }

            if let text = value(after: "-backupEditToday") {
                let effect = try? await store.updateEntry(AppClock.today(), .text(text))
                if effect?.dirty == true { manager.markDirty() }
                log("edited today dirty=\(effect?.dirty == true)")
            }
            if args.contains("-backupNow") {
                // A scene blip at launch can cancel a run (by design); try again until one completes.
                for attempt in 1...5 {
                    while !manager.isActive { try? await Task.sleep(for: .milliseconds(100)) }
                    await manager.backUpNow()
                    log("attempt \(attempt) outcome=\(manager.lastOutcome ?? "none")")
                    if manager.lastOutcome != "cancelled" { break }
                }
                let index = manager.index
                log(
                    "backupNow done snapshots=\(index.snapshots.count) blobs=\(index.knownBlobs.count) pending=\(index.pendingChanges) outcome=\(manager.lastOutcome ?? "none") error=\(index.lastError?.rawValue ?? "none") paused=\(index.cleanupPaused)"
                )
                if let folder = value(after: "-backupFolder") { listFolder(folder) }
            }
            if args.contains("-dumpBackupIndex") { dumpIndex(manager.index) }
        }

        private static func listFolder(_ path: String) {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
                return
            }
            let prefix = root.resolvingSymlinksInPath().path + "/"
            var lines: [String] = []
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                lines.append(
                    "\(url.resolvingSymlinksInPath().path.replacingOccurrences(of: prefix, with: "")) \(values?.fileSize ?? 0)"
                )
            }
            log("folder listing:\n" + lines.sorted().joined(separator: "\n"))
        }

        private static func dumpIndex(_ index: BackupIndex) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(index),
                let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            else { return }
            try? data.write(to: documents.appending(path: "backup-index-dump.json", directoryHint: .notDirectory))
        }

        private static func log(_ line: String) {
            logger.notice("\(line, privacy: .public)")
            guard
                let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            else { return }
            let file = documents.appending(path: "backup-auto-debug.txt", directoryHint: .notDirectory)
            let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            try? (existing + line + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
#endif
