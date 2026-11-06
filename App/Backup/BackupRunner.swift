import Foundation
import OSLog
import ReytKit

enum BackupRunError: Error, Equatable {
    case coded(BackupErrorCode)
    /// The journal changed under the run (a photo vanished after the snapshot was taken): try again, no error shown.
    case sourceChanged
    case cancelled
}

/// One backup run, start to finish, off the main actor. It either ends with a verified snapshot in the folder
/// (and only then deletes anything) or leaves the folder as it found it, apart from blobs that were proven good.
///
/// Order: snapshot payload, missing blobs, encrypt + verify the snapshot, move it in and re-read it, confirm every
/// referenced blob is listed, then and only then the prune and blob cleanup chosen by `BackupPlan`.
struct BackupRunner: Sendable {
    struct Input: Sendable {
        let store: JournalStore
        let paths: Paths
        let generation: URL
        let destination: any BackupDestination
        let passphrase: String
        let dataKey: Data
        let index: BackupIndex
        let today: DateKey
        let now: Date
        let appVersion: String
    }

    struct Output: Sendable {
        /// The index as the run leaves it: partial progress (blobs proven good) is kept on failure, snapshots
        /// and deletions only change on success.
        var index: BackupIndex
        var error: BackupRunError?
        var snapshotName: String?
    }

    private static let logger = Logger(subsystem: "local.mitchel.bereyt", category: "backup")

    func run(_ input: Input) async -> Output {
        var index = input.index
        var written: String?  // a snapshot file this run moved in and has not yet proven good
        let scratch: URL
        do { scratch = try ScratchSpace.make() } catch { return Output(index: index, error: .coded(.other)) }
        defer { ScratchSpace.remove(scratch) }
        do {
            if await input.store.isReadOnly { throw BackupRunError.cancelled }
            var items = try input.destination.list()
            index.reconcile(with: items)

            // (1) the snapshot payload: records and manifest, no photos, blob names and the data key inside.
            let payload = scratch.appending(path: "payload", directoryHint: .isDirectory)
            let options = ArchiveWriter.Options(
                kind: .snapshot, appVersion: input.appVersion, lineageID: index.lineageID, createdAt: input.now,
                dataKey: input.dataKey)
            let manifest = try await ArchiveWriter(paths: input.paths, generation: input.generation)
                .write(from: input.store, to: payload, options: options)
            try check()
            let referenced = Set(manifest.attachments.compactMap(\.blob))
            guard referenced.count <= manifest.attachments.count,
                manifest.attachments.allSatisfy({ $0.blob != nil })
            else { throw BackupRunError.coded(.other) }

            // (2) every photo the snapshot needs that the folder doesn't hold yet.
            let present = Set(
                items.filter { $0.area == .blobs && ($0.bytes ?? 1) > 0 }.compactMap {
                    BlobNaming.name(fromFileName: $0.name)
                })
            let data = try ArchiveReader.readData(in: payload, maxBytes: ArchiveValidator.Limits.default.perFileBytes)
            let pathByID = Dictionary(uniqueKeysWithValues: data.attachments.map { ($0.id, $0.relativePath) })
            var jobs: [String: BlobStore.Job] = [:]
            for item in manifest.attachments {
                guard let blob = item.blob, !present.contains(blob), jobs[blob] == nil else { continue }
                guard let relative = pathByID[item.id],
                    let source = try? input.paths.resolveAttachment(relativePath: relative, in: input.generation),
                    FileManager.default.fileExists(atPath: source.path)
                else { throw BackupRunError.sourceChanged }
                jobs[blob] = BlobStore.Job(name: blob, sha256: item.sha256, source: source)
            }
            let blobStore = BlobStore(destination: input.destination)
            var uploaded: [String] = []
            for job in jobs.values.sorted(by: { $0.name < $1.name }) {
                try check()
                index.knownBlobs[job.name] = try blobStore.upload(job, dataKey: input.dataKey, scratch: scratch)
                uploaded.append(job.name)
            }

            // (3) the snapshot, sealed with the passphrase, proven readable before and after it is moved in.
            try check()
            let sealed = scratch.appending(path: "snapshot.aea", directoryHint: .notDirectory)
            try ArchiveCrypto.encrypt(directory: payload, to: sealed, passphrase: input.passphrase)
            try? FileManager.default.removeItem(at: payload)  // plaintext gone as soon as it is sealed
            try verify(sealed, input: input, referenced: referenced, scratch: scratch)
            try check()
            let name = BackupFolderNames.snapshotFileName(day: input.today)
            let relative = "\(BackupFolderNames.snapshots)/\(name)"
            try input.destination.coordinatedWrite(from: sealed, to: relative)
            written = name
            try input.destination.coordinatedRead(relative) { url in
                try verify(url, input: input, referenced: referenced, scratch: scratch)
            }

            // (4) every blob the snapshot points at is in the folder.
            items = try input.destination.list()
            let listedBlobs = BackupIndex.blobNames(in: items)
            guard referenced.isSubset(of: listedBlobs) else { throw BackupRunError.coded(.verifyFailed) }
            let known = KnownSnapshot(
                name: name, dayKey: input.today, lineageID: index.lineageID, kind: .daily, verified: true,
                createdAt: input.now, referencedBlobNames: referenced)
            index.reconcile(with: items)
            index.snapshots.append(known)
            written = nil  // proven good from here on

            // (5) only now: prune and clean up, as `BackupPlan` decides.
            let cleanup = BackupPlan.cleanup(
                runVerified: true, newSnapshot: name, snapshots: index.snapshots,
                folderSnapshotNames: BackupIndex.snapshotNames(in: items), folderBlobNames: listedBlobs,
                now: input.now)
            apply(cleanup, to: &index, destination: input.destination)

            // (6) the index.
            index.lastSnapshotName = name
            index.lastSnapshotWrittenAt = Date.now
            index.latestRunBlobs = uploaded
            index.lastError = nil
            return Output(index: index, error: nil, snapshotName: name)
        } catch {
            if let written { try? input.destination.remove("\(BackupFolderNames.snapshots)/\(written)") }
            return Output(index: index, error: Self.map(error))
        }
    }

    private func check() throws {
        if Task.isCancelled { throw BackupRunError.cancelled }
    }

    /// Decrypts with the passphrase and validates like a restore would, and checks the snapshot carries the key and
    /// the blob list this run expects. The plaintext is removed straight after.
    private func verify(_ archive: URL, input: Input, referenced: Set<String>, scratch: URL) throws {
        let directory = scratch.appending(path: "verify-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try ArchiveCrypto.decrypt(archive: archive, passphrase: input.passphrase, into: directory)
            let validated = try ArchiveValidator.validate(directory: directory, verifyAttachmentFiles: false)
            guard validated.manifest.kind == .snapshot,
                Set(validated.manifest.attachments.compactMap(\.blob)) == referenced,
                try SnapshotBlobs.readDataKey(in: directory) == input.dataKey
            else { throw BackupRunError.coded(.verifyFailed) }
        } catch let error as BackupRunError {
            throw error
        } catch {
            throw BackupRunError.coded(.verifyFailed)
        }
    }

    private func apply(_ cleanup: BackupPlan.Cleanup, to index: inout BackupIndex, destination: any BackupDestination) {
        let byName = Dictionary(index.snapshots.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for name in cleanup.snapshotsToDelete {
            let folder = byName[name]?.kind == .preRestore ? BackupFolderNames.preRestore : BackupFolderNames.snapshots
            if (try? destination.remove("\(folder)/\(name)")) != nil {
                index.snapshots.removeAll { $0.name == name }
            }
        }
        for blob in cleanup.blobsToDelete {
            guard let relative = BlobNaming.relativePath(for: blob) else { continue }
            if (try? destination.remove(relative)) != nil { index.knownBlobs[blob] = nil }
        }
        index.cleanupPaused = cleanup.cleanupPaused
    }

    private static func map(_ error: Error) -> BackupRunError {
        switch error {
        case let error as BackupRunError: return error
        case is CancellationError: return .cancelled
        case BackupDestinationError.folderMissing: return .coded(.folderMissing)
        case BackupDestinationError.storageFull: return .coded(.storageFull)
        case ArchiveError.storeChanged: return .sourceChanged
        case JournalStoreError.readOnly: return .cancelled
        default:
            logger.error("run failed: \(String(describing: type(of: error)), privacy: .public)")
            return .coded(.uploadFailed)
        }
    }
}
