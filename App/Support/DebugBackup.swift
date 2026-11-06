#if DEBUG
    import Foundation
    import OSLog
    import ReytKit

    /// Simulator-only drivers for the backup flows, so they can be exercised without the system pickers:
    /// `-debugPassphrase <p>`, `-exportTo <path>`, `-restoreFrom <path>`, `-restoreBegin <path>` (sheet at the passphrase step), `-restoreSnapshot <name>` (from `-backupFolder`; add `-autoConfirmRestore` to go through),
    /// `-undoLastRestore`. Results (counts and outcomes, never journal text) go to the log and to
    /// `Documents/backup-debug.txt`.
    enum DebugBackup {
        private static let logger = Logger(subsystem: "local.mitchel.bereyt", category: "debug-backup")

        private static func value(after flag: String) -> String? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }

        @MainActor
        static func runIfRequested(host: ContainerHost, restore: RestoreCoordinator) async {
            let args = CommandLine.arguments
            let passphrase = value(after: "-debugPassphrase")
            let wants =
                args.contains("-exportTo") || args.contains("-restoreFrom") || args.contains("-restoreSnapshot")
                || args.contains("-undoLastRestore")
                || args.contains("-restoreBegin")
                || passphrase != nil
            guard wants else { return }
            if let passphrase {
                PassphraseStore.debugOverride = passphrase
                try? PassphraseStore().set(passphrase)
            }

            var waited = 0
            while host.store == nil, waited < 400 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            guard let store = host.store else { return log("store never opened") }
            await logCounts("before", store: store, host: host)

            if let path = value(after: "-exportTo"), let passphrase, let generation = host.generationURL {
                do {
                    let result = try await PortableExporter(paths: host.paths, generation: generation)
                        .export(from: store, passphrase: passphrase, to: URL(fileURLWithPath: path))
                    log("export ok skippedPhotos=\(result.skippedAttachments)")
                } catch {
                    log("export failed \(String(describing: error))")
                }
            }

            // `-restoreBegin <path>` stops at the passphrase step of the restore sheet.
            if let path = value(after: "-restoreBegin") { restore.beginRestore(from: URL(fileURLWithPath: path)) }

            if let path = value(after: "-restoreFrom"), let passphrase {
                let url = URL(fileURLWithPath: path)
                restore.beginRestore(from: url)
                await restore.openFile(url, passphrase: passphrase)
                log("restore prepare phase=\(restore.phase)")
                if args.contains("-autoConfirmRestore"), restore.phase == .ready {
                    await restore.confirmRestore()
                    log("restore finished phase=\(restore.phase) undoAvailable=\(restore.undoAvailable)")
                }
            }

            if let name = value(after: "-restoreSnapshot"), let passphrase {
                let area: BackupArea = name.hasPrefix("be-reyt-pre-restore-") ? .preRestore : .snapshots
                let input = RestoreInput.snapshot(SnapshotRef(name: name, area: area))
                restore.beginRestore(fromSnapshot: SnapshotRef(name: name, area: area))
                await restore.open(input, passphrase: passphrase)
                log("restore snapshot prepare phase=\(restore.phase)")
                if args.contains("-autoConfirmRestore"), restore.phase == .ready {
                    await restore.confirmRestore()
                    log("restore snapshot finished phase=\(restore.phase) undoAvailable=\(restore.undoAvailable)")
                }
            }

            if args.contains("-undoLastRestore") {
                do {
                    try await restore.undoLastRestore()
                    log("undo ok")
                } catch {
                    log("undo failed \(String(describing: error))")
                }
            }
            if let current = host.store { await logCounts("after", store: current, host: host) }
        }

        @MainActor
        private static func logCounts(_ label: String, store: JournalStore, host: ContainerHost) async {
            guard let data = try? await store.archiveSnapshot().data else { return }
            let c = ArchiveManifest.Counts(data)
            let photoFiles =
                host.generationURL.map {
                    (try? FileManager.default.contentsOfDirectory(atPath: host.paths.attachments(in: $0).path).count)
                        ?? -1
                } ?? -1
            log(
                "counts \(label) gen=\(host.generationID ?? "?") entries=\(c.entries) attachments=\(c.attachments) photoFiles=\(photoFiles) intentions=\(c.intentions) reviews=\(c.reviews) workouts=\(c.workouts) range=\(data.dateRange.map { "\($0.first)..\($0.last)" } ?? "none")"
            )
        }

        private static func log(_ line: String) {
            logger.notice("\(line, privacy: .public)")
            guard
                let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            else { return }
            let file = documents.appending(path: "backup-debug.txt", directoryHint: .notDirectory)
            let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            try? (existing + line + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
#endif
