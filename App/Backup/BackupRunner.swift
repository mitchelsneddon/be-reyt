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
        /// `.preRestore` is the safety copy before a restore: it runs while the store is read-only, lands in
        /// `pre-restore/`, never replaces or prunes anything and leaves the daily bookkeeping alone.
        var kind: KnownSnapshot.Kind = .daily
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
            if input.kind == .daily, await input.store.isReadOnly { throw BackupRunError.cancelled }
            var items = try input.destination.list()
            index.reconcile(with: items)

            // (1) + (2) the snapshot payload and every photo it needs that the folder doesn't hold yet. A photo whose
            // bytes don't match its checksum is left out with a warning, then the payload is written again without it.
            let payload = scratch.appending(path: "payload", directoryHint: .isDirectory)
            var excluded = Set<UUID>()
            var staged: Staged?
            var uploadedEarlier: [String] = []
            for _ in 0..<Self.maxStagingPasses where staged == nil {
                do {
                    staged = try await stage(
                        input: input, index: &index, items: items, payload: payload, scratch: scratch,
                        excluded: excluded, alreadyUploaded: uploadedEarlier)
                } catch let bad as MismatchedPhotos {
                    Self.logger.warning("skipping \(bad.ids.count, privacy: .public) photo(s) that fail their checksum")
                    excluded.formUnion(bad.ids)
                    uploadedEarlier += bad.uploaded
                }
            }
            guard let staged else { throw BackupRunError.coded(.photoUnreadable) }
            let referenced = staged.referenced
            let uploaded = uploadedEarlier + staged.uploaded

            // (3) the snapshot, sealed with the passphrase, proven readable before and after it is moved in.
            try check()
            let sealed = scratch.appending(path: "snapshot.aea", directoryHint: .notDirectory)
            try ArchiveCrypto.encrypt(directory: payload, to: sealed, passphrase: input.passphrase)
            try? FileManager.default.removeItem(at: payload)  // plaintext gone as soon as it is sealed
            try verify(sealed, input: input, referenced: referenced, scratch: scratch)
            try check()
            let isPreRestore = input.kind == .preRestore
            let folder = isPreRestore ? BackupFolderNames.preRestore : BackupFolderNames.snapshots
            let name =
                isPreRestore
                ? BackupFolderNames.preRestoreFileName(day: input.today)
                : BackupFolderNames.snapshotFileName(day: input.today)
            let relative = "\(folder)/\(name)"
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
                name: name, dayKey: input.today, lineageID: index.lineageID, kind: input.kind, verified: true,
                createdAt: input.now, referencedBlobNames: referenced)
            index.reconcile(with: items)
            index.snapshots.append(known)
            written = nil  // proven good from here on

            // (5) only now: prune and clean up, as `BackupPlan` decides. A safety copy deletes nothing; the next
            // daily run expires it after 30 days.
            if !isPreRestore {
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
            }
            return Output(index: index, error: nil, snapshotName: name)
        } catch {
            if let written {
                let folder = input.kind == .preRestore ? BackupFolderNames.preRestore : BackupFolderNames.snapshots
                try? input.destination.remove("\(folder)/\(written)")
            }
            return Output(index: index, error: Self.map(error))
        }
    }

    private static let maxStagingPasses = 3

    private struct Staged {
        let referenced: Set<String>
        let uploaded: [String]
    }

    private struct MismatchedPhotos: Error {
        let ids: Set<UUID>
        let uploaded: [String]
    }

    /// One pass of steps (1) and (2). Throws `MismatchedPhotos` after uploading everything else, so the caller can
    /// write the payload again without those photos.
    private func stage(
        input: Input, index: inout BackupIndex, items: [DestinationItem], payload: URL, scratch: URL,
        excluded: Set<UUID>,
        alreadyUploaded: [String]
    ) async throws -> Staged {
        try? FileManager.default.removeItem(at: payload)
        var options = ArchiveWriter.Options(
            kind: .snapshot, appVersion: input.appVersion, lineageID: index.lineageID, createdAt: input.now,
            dataKey: input.dataKey)
        options.excludedAttachmentIDs = excluded
        let manifest = try await ArchiveWriter(paths: input.paths, generation: input.generation)
            .write(from: input.store, to: payload, options: options)
        try check()
        let referenced = Set(manifest.attachments.compactMap(\.blob))
        guard referenced.count <= manifest.attachments.count,
            manifest.attachments.allSatisfy({ $0.blob != nil })
        else { throw BackupRunError.coded(.other) }

        let present = Set(alreadyUploaded).union(
            items.filter { $0.area == .blobs && ($0.bytes ?? 1) > 0 }.compactMap {
                BlobNaming.name(fromFileName: $0.name)
            }
        )
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
        var mismatched = Set<String>()
        for job in jobs.values.sorted(by: { $0.name < $1.name }) {
            try check()
            do {
                index.knownBlobs[job.name] = try blobStore.upload(job, dataKey: input.dataKey, scratch: scratch)
                uploaded.append(job.name)
            } catch let bad as BlobStore.ChecksumMismatch {
                mismatched.insert(bad.blob)
            }
        }
        if !mismatched.isEmpty {
            let ids = manifest.attachments.filter { $0.blob.map(mismatched.contains) ?? false }.map(\.id)
            throw MismatchedPhotos(ids: Set(ids), uploaded: uploaded)
        }
        return Staged(referenced: referenced, uploaded: uploaded)
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
