import Foundation
import OSLog
import Observation
import ReytKit

// Restore orchestration. The swap itself (build a new generation, flip the pointer) is `GenerationSwitcher`;
// this decides the order around it so a failure at any point leaves the phone exactly as it was.

enum RestoreFailure: Error, Equatable {
    case wrongPassphrase
    case notABackup
    case newerVersion
    case damaged
    case noPassphrase
    case safetyCopyFailed
    case switchFailed
    /// A photo the backup points at is missing, damaged or could not be fetched.
    case photoUnreadable
    case folderMissing
    /// The snapshot file could not be read (an iCloud download that did not finish, for example).
    case unreachable
    case busy
    case nothingToUndo
}

/// Where a restore's payload comes from. S14b has one source (an encrypted file); the backup-set browser adds its
/// own. `extract` fills an empty directory with `manifest.json`, `data.json` and `attachments/`.
protocol RestorePayloadSource: Sendable {
    var displayName: String { get }
    func extract(into directory: URL) async throws
}

/// A snapshot in the backup folder: which area it is in and its file name.
struct SnapshotRef: Equatable, Hashable, Sendable {
    let name: String
    let area: BackupArea
    var relativePath: String { "\(area.folder)/\(name)" }
}

/// What the user picked to restore from.
enum RestoreInput: Equatable, Sendable {
    case file(URL)
    case snapshot(SnapshotRef)
}

/// A snapshot of the backup set: the snapshot file, then every photo it points at, each fetched with a coordinated
/// read (iCloud downloads an evicted file first), decrypted with that snapshot's own data key and checked against
/// the manifest's SHA256, then staged as `attachments/` so the payload validates like a portable archive.
struct SnapshotSource: RestorePayloadSource {
    let destination: any BackupDestination
    let ref: SnapshotRef
    let passphrase: String
    var displayName: String { ref.name }

    func extract(into directory: URL) async throws {
        let destination = destination
        let ref = ref
        let passphrase = passphrase
        try await Task.detached(priority: .userInitiated) {
            try destination.coordinatedRead(ref.relativePath) { readable in
                try ArchiveCrypto.decrypt(archive: readable, passphrase: passphrase, into: directory)
            }
            let manifest = try ArchiveReader.readManifest(
                in: directory, maxBytes: ArchiveValidator.Limits.default.perFileBytes)
            guard manifest.kind == .snapshot else { throw ArchiveError.notAnArchive }
            let key = try SnapshotBlobs.readDataKey(in: directory)
            do {
                try SnapshotBlobs.stage(manifest: manifest, dataKey: key, into: directory) { blob in
                    guard let relative = BlobNaming.relativePath(for: blob) else {
                        throw RestoreFailure.photoUnreadable
                    }
                    // shortcut: the URL outlives the coordinated read (the file stays where iCloud downloaded it
                    // for the seconds staging takes); a blob evicted in between fails the restore, nothing changed
                    return try destination.coordinatedRead(relative) { $0 }
                }
            } catch {
                throw RestoreFailure.photoUnreadable
            }
        }.value
    }
}

struct EncryptedFileSource: RestorePayloadSource {
    let url: URL
    let passphrase: String
    var displayName: String { url.lastPathComponent }

    func extract(into directory: URL) async throws {
        let url = url
        let passphrase = passphrase
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // A coordinated read makes iCloud Drive download the file first if it is only a placeholder.
            var coordinationError: NSError?
            var result: Result<Void, Error> = .failure(CocoaError(.fileReadUnknown))
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                result = Result {
                    try ArchiveCrypto.decrypt(archive: readable, passphrase: passphrase, into: directory)
                }
            }
            if let coordinationError { throw coordinationError }
            try result.get()
        }.value
    }
}

/// A decrypted, validated archive waiting for the user's decision. The plaintext sits in `scratch` until
/// `commit` or `discard`.
struct RestorePreview: Sendable {
    let archive: ValidatedArchive
    let scratch: URL
    let sourceName: String
    /// The passphrase the archive opened with; the fallback for a pre-restore copy when none is stored.
    let passphrase: String
    /// Set when it came from the backup set: the file it was read from.
    var snapshot: SnapshotRef?
    /// Set for a backup-set snapshot: the data key it carried.
    var dataKey: Data?

    var counts: ArchiveManifest.Counts { archive.counts }
    var dateRange: ArchiveManifest.DateRange? { archive.dateRange }
    var warnings: [String] { archive.warnings }
    var skippedPhotos: Int { warnings.filter { $0 == ArchiveWarning.missingAttachment }.count }
}

@MainActor @Observable
final class RestoreCoordinator {
    enum Phase: Equatable {
        case idle
        case needsPassphrase(RestoreInput)
        case preparing
        case ready
        case restoring
        case undoing
        case failed(RestoreFailure, retry: RestoreInput?)
    }

    static let maxPreRestoreCopies = 3

    private(set) var phase: Phase = .idle
    private(set) var preview: RestorePreview?
    /// Shown once after a restore or undo rebuilt the app, until dismissed.
    private(set) var completionNote: String?
    /// True when the note says an undo happened (the banner shows an undo arrow instead of a check).
    private(set) var completionIsUndo = false
    private(set) var undoAvailable = false

    /// Asked once after a successful restore; nil when there is nothing to ask.
    enum PassphraseQuestion: Equatable { case useTyped, keepOrSwitch }
    private(set) var passphraseQuestion: PassphraseQuestion?
    private(set) var passphraseSaveFailed = false
    /// Set by the app: saves a passphrase as the backup passphrase (and rotates the data key as for any change).
    @ObservationIgnored var adoptPassphrase: @MainActor (String) throws -> Void = { _ in }
    /// The restore passphrase, in memory only until the question is answered. Never persisted anywhere else.
    @ObservationIgnored private var typedPassphrase: String?

    @ObservationIgnored private var isSwapping = false
    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let quiescer: Quiescer
    @ObservationIgnored private let passphrases: PassphraseStore
    @ObservationIgnored private let backup: BackupManager
    @ObservationIgnored private var hooks: [@Sendable () async -> Void] = []
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "restore")

    init(
        host: ContainerHost, quiescer: Quiescer, backup: BackupManager,
        passphrases: PassphraseStore = PassphraseStore()
    ) {
        self.host = host
        self.quiescer = quiescer
        self.backup = backup
        self.passphrases = passphrases
        refreshUndoAvailability()
    }

    /// Runs after every restore or undo, once the app has reopened at the new generation. S9 (health re-sync)
    /// and S10 (reminders) register theirs; narrative validation is built in.
    func registerPostRestoreHook(_ hook: @escaping @Sendable () async -> Void) { hooks.append(hook) }

    func dismissCompletionNote() { completionNote = nil }

    #if DEBUG
        func debugShowNote(undone: Bool) {
            completionNote = undone ? Copy.Restore.undoneNote : Copy.Restore.doneNote(entries: 3)
            completionIsUndo = undone
        }
    #endif

    // MARK: Flow state

    func beginRestore(from url: URL) {
        discardPreview()
        phase = .needsPassphrase(.file(url))
    }

    /// The restore browser picked a snapshot from the backup set.
    func beginRestore(fromSnapshot ref: SnapshotRef) {
        discardPreview()
        phase = .needsPassphrase(.snapshot(ref))
    }

    /// Back to nothing: removes any plaintext and closes the flow.
    func cancel() {
        guard phase != .restoring, phase != .undoing else { return }
        discardPreview()
        phase = .idle
    }

    func retry(_ input: RestoreInput) { phase = .needsPassphrase(input) }

    /// UI entry: decrypt and validate `input`, then move to `.ready` or `.failed`.
    func open(_ input: RestoreInput, passphrase: String) async {
        phase = .preparing
        do {
            switch input {
            case .file(let url): preview = try await prepare(from: url, passphrase: passphrase)
            case .snapshot(let ref): preview = try await prepare(fromSnapshot: ref, passphrase: passphrase)
            }
            phase = .ready
        } catch {
            phase = .failed(Self.failure(for: error), retry: input)
        }
    }

    func openFile(_ url: URL, passphrase: String) async { await open(.file(url), passphrase: passphrase) }

    /// UI entry: the user confirmed.
    func confirmRestore() async {
        guard let preview, phase == .ready else { return }
        phase = .restoring
        do {
            try await commit(preview)
            phase = .idle
        } catch {
            phase = .failed(Self.failure(for: error), retry: nil)
            self.preview = preview  // the preview is still valid; the sheet can offer another go
        }
    }

    // MARK: Prepare

    /// Decrypts into a fresh scratch directory and validates, photos included. On failure the scratch directory is
    /// removed.
    func prepare(
        from source: some RestorePayloadSource, passphrase: String, snapshot: SnapshotRef? = nil
    ) async throws -> RestorePreview {
        let scratch = try ScratchSpace.make()
        do {
            try await source.extract(into: scratch)
            let archive = try await Task.detached(priority: .userInitiated) {
                try ArchiveValidator.validate(directory: scratch, verifyAttachmentFiles: true)
            }.value
            let key = snapshot == nil ? nil : try SnapshotBlobs.readDataKey(in: scratch)
            return RestorePreview(
                archive: archive, scratch: scratch, sourceName: source.displayName, passphrase: passphrase,
                snapshot: snapshot, dataKey: key)
        } catch {
            ScratchSpace.remove(scratch)
            throw error
        }
    }

    func prepare(from archiveURL: URL, passphrase: String) async throws -> RestorePreview {
        try await prepare(from: EncryptedFileSource(url: archiveURL, passphrase: passphrase), passphrase: passphrase)
    }

    /// A snapshot of the backup set: downloads it and its photos if iCloud had evicted them, checks every photo,
    /// then previews. Any photo that is missing or fails its checksum fails the whole preparation.
    func prepare(fromSnapshot ref: SnapshotRef, passphrase: String) async throws -> RestorePreview {
        let destination = try backup.openDestination()
        return try await prepare(
            from: SnapshotSource(destination: destination, ref: ref, passphrase: passphrase), passphrase: passphrase,
            snapshot: ref)
    }

    func discardPreview() {
        ScratchSpace.remove(preview?.scratch)
        preview = nil
    }

    // MARK: Commit

    /// Replaces the whole journal with the previewed archive.
    func commit(_ preview: RestorePreview) async throws {
        try await switchGeneration(
            to: .archive(preview.archive), fallbackPassphrase: preview.passphrase, source: preview)
        ScratchSpace.remove(preview.scratch)
        self.preview = nil
        completionNote = Copy.Restore.doneNote(entries: preview.counts.entries)
        completionIsUndo = false
        askPassphraseQuestion(typed: preview.passphrase)
    }

    private func askPassphraseQuestion(typed: String) {
        let stored = passphrases.stored()
        if stored == nil {
            passphraseQuestion = .useTyped
        } else if stored != typed {
            passphraseQuestion = .keepOrSwitch
        } else {
            return
        }
        typedPassphrase = typed
    }

    /// `adopt` true saves the typed passphrase; false leaves things as they are. Either way the question ends.
    func answerPassphraseQuestion(adopt: Bool) {
        let typed = typedPassphrase
        typedPassphrase = nil
        passphraseQuestion = nil
        guard adopt, let typed else { return }
        do { try adoptPassphrase(typed) } catch { passphraseSaveFailed = true }
    }

    func dismissPassphraseSaveFailure() { passphraseSaveFailed = false }

    // MARK: Undo

    private var paths: Paths { host.paths }

    func refreshUndoAvailability() {
        undoAvailable = recoveryTarget() != nil
    }

    private func recoveryTarget() -> String? {
        guard let record = RecoveryRecord.load(from: paths), record.isAvailable(now: .now),
            record.generationID != host.paths.currentGenerationID(),
            FileManager.default.fileExists(atPath: paths.store(in: paths.generation(record.generationID)).path)
        else { return nil }
        return record.generationID
    }

    /// Flips back to the generation the last restore replaced. Anything written since the restore is lost, so the
    /// current journal gets the same safety copy first.
    func undoLastRestore() async throws {
        guard let target = recoveryTarget() else { throw RestoreFailure.nothingToUndo }
        phase = .undoing
        defer { if phase == .undoing { phase = .idle } }
        do {
            try await switchGeneration(to: .previous(target), fallbackPassphrase: nil, source: nil)
        } catch {
            phase = .failed(Self.failure(for: error), retry: nil)
            throw error
        }
        completionNote = Copy.Restore.undoneNote
        completionIsUndo = true
    }

    // MARK: The swap

    private enum Target {
        case archive(ValidatedArchive)
        case previous(String)
    }

    private func switchGeneration(to target: Target, fallbackPassphrase: String?, source: RestorePreview?) async throws
    {
        guard !isSwapping else { throw RestoreFailure.busy }
        isSwapping = true
        defer { isSwapping = false }
        guard let store = host.store, let attachments = host.attachments, let currentID = host.generationID,
            let currentURL = host.generationURL
        else { throw RestoreFailure.switchFailed }
        let switcher = GenerationSwitcher(paths: paths)
        let priorRecord = RecoveryRecord.load(from: paths)

        // (i) quiesce: pending edits are written, health and backups stop, then the store refuses every write.
        await quiescer.quiesce(store: store, attachments: attachments)

        var built: BuiltGeneration?
        var flipped = false
        do {
            // (ii) safety copy of what is about to be replaced.
            do {
                try await writeSafetyCopy(
                    store: store, generation: currentURL, passphrase: passphrases.stored() ?? fallbackPassphrase)
            } catch let failure as RestoreFailure {
                throw failure
            } catch {
                logger.error("safety copy failed: \(String(describing: type(of: error)), privacy: .public)")
                throw RestoreFailure.safetyCopyFailed
            }

            // (iii) build the new generation beside the current one, then (iv) record the old one and flip.
            let targetID: String
            switch target {
            case .archive(let archive):
                let generation = try await Task.detached(priority: .userInitiated) { try switcher.build(from: archive) }
                    .value
                built = generation
                targetID = generation.id
                try RecoveryRecord(generationID: currentID, recordedAt: .now).save(to: paths)
            case .previous(let id):
                targetID = id
            }
            try switcher.flip(to: targetID)
            flipped = true
            if case .previous = target { RecoveryRecord.clear(from: paths) }

            // (v) the root view is keyed on the generation id: reopening rebuilds everything.
            try host.reopenCurrent()
        } catch {
            await rollback(
                switcher: switcher, previousID: currentID, built: built, flipped: flipped, priorRecord: priorRecord)
            await quiescer.resume(store: store, reopenStore: paths.currentGenerationID() == currentID)
            refreshUndoAvailability()
            if error is RestoreFailure { throw error }
            logger.error("switch failed: \(String(describing: type(of: error)), privacy: .public)")
            throw RestoreFailure.switchFailed
        }

        // (vi) the backup set learns the journal changed under it: new lineage, the restored snapshot's references,
        // this phone's data key (or the snapshot's when there is none), and a fresh daily snapshot queued.
        backup.didRestore(
            snapshot: source?.snapshot, manifest: source?.archive.manifest, dataKey: source?.dataKey)

        // (vii) hooks, then validate every restored narrative against its week's input (mismatches purge).
        if let newStore = host.store, case .archive(let archive) = target {
            for review in archive.data.reviews {
                if let week = DateKey(review.weekStartKey) {
                    _ = try? await newStore.validateNarrative(weekStart: week)
                }
            }
        }
        for hook in hooks { await hook() }
        refreshUndoAvailability()
    }

    private func rollback(
        switcher: GenerationSwitcher, previousID: String, built: BuiltGeneration?, flipped: Bool,
        priorRecord: RecoveryRecord?
    ) async {
        if flipped { try? switcher.flip(to: previousID) }
        if let built { try? switcher.abandon(built.id) }
        if let priorRecord { try? priorRecord.save(to: paths) } else { RecoveryRecord.clear(from: paths) }
    }

    // MARK: Safety copy

    /// What is about to be replaced, saved first. With an automatic-backup folder: a full verified run into
    /// `pre-restore/` (snapshot plus any photos the folder lacks), exempt from pruning for 30 days; it must verify
    /// or the restore stops. Without one: a portable export into `Device/pre-restore/`, newest three kept. Skipped
    /// when the journal holds nothing worth keeping (a new phone, or a fresh install).
    private func writeSafetyCopy(store: JournalStore, generation: URL, passphrase: String?) async throws {
        let snapshot = try await store.archiveSnapshot()
        let data = snapshot.data
        let hasContent =
            !data.entries.isEmpty || !data.attachments.isEmpty || !data.tags.isEmpty || !data.intentions.isEmpty
            || !data.reviews.isEmpty || !data.workouts.isEmpty || !data.importRecords.isEmpty
        guard hasContent else { return }
        if backup.hasDestination, let passphrase {
            do {
                try await backup.writePreRestoreCopy(passphrase: passphrase)
                return
            } catch BackupRunError.coded(.folderMissing) {
                // the folder is gone: fall through to the on-phone copy rather than block the restore for good
            } catch BackupDestinationError.folderMissing {
            } catch BackupDestinationError.notConfigured {
            } catch {
                logger.error("pre-restore backup failed: \(String(describing: error), privacy: .public)")
                throw RestoreFailure.safetyCopyFailed
            }
        }
        guard let passphrase else { throw RestoreFailure.noPassphrase }
        let directory = paths.deviceRoot.appending(path: "pre-restore", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: ArchiveCrypto.preRestoreFileName(), directoryHint: .notDirectory)
        _ = try await PortableExporter(paths: paths, generation: generation)
            .export(from: store, passphrase: passphrase, to: destination)
        Self.pruneSafetyCopies(in: directory, keep: Self.maxPreRestoreCopies)
    }

    nonisolated static func pruneSafetyCopies(in directory: URL, keep: Int) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files =
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("be-reyt-pre-restore-") && $0.pathExtension == "aea" }
        let newestFirst = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in newestFirst.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    // MARK: Errors

    static func failure(for error: Error) -> RestoreFailure {
        if let failure = error as? RestoreFailure { return failure }
        switch error {
        case ArchiveCryptoError.wrongPassphrase, ArchiveCryptoError.passphraseTooLong: return .wrongPassphrase
        case ArchiveCryptoError.notEncryptedArchive, ArchiveError.notAnArchive: return .notABackup
        case ArchiveError.newerVersion: return .newerVersion
        case BackupDestinationError.folderMissing, BackupDestinationError.notConfigured: return .folderMissing
        case BackupDestinationError.io: return .unreachable
        default: return .damaged
        }
    }
}
