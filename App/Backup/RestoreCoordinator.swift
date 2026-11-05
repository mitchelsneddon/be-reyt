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
    case busy
    case nothingToUndo
}

/// Where a restore's payload comes from. S14b has one source (an encrypted file); the backup-set browser adds its
/// own. `extract` fills an empty directory with `manifest.json`, `data.json` and `attachments/`.
protocol RestorePayloadSource: Sendable {
    var displayName: String { get }
    func extract(into directory: URL) async throws
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

    var counts: ArchiveManifest.Counts { archive.counts }
    var dateRange: ArchiveManifest.DateRange? { archive.dateRange }
    var warnings: [String] { archive.warnings }
    var skippedPhotos: Int { warnings.filter { $0 == ArchiveWarning.missingAttachment }.count }
}

@MainActor @Observable
final class RestoreCoordinator {
    enum Phase: Equatable {
        case idle
        case needsPassphrase(URL)
        case preparing
        case ready
        case restoring
        case undoing
        case failed(RestoreFailure, retry: URL?)
    }

    static let maxPreRestoreCopies = 3

    private(set) var phase: Phase = .idle
    private(set) var preview: RestorePreview?
    /// Shown once after a restore or undo rebuilt the app, until dismissed.
    private(set) var completionNote: String?
    private(set) var undoAvailable = false

    @ObservationIgnored private var isSwapping = false
    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let passphrases: PassphraseStore
    @ObservationIgnored private var hooks: [@Sendable () async -> Void] = []
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "restore")

    init(host: ContainerHost, events: JournalEvents, passphrases: PassphraseStore = PassphraseStore()) {
        self.host = host
        self.events = events
        self.passphrases = passphrases
        refreshUndoAvailability()
    }

    /// Runs after every restore or undo, once the app has reopened at the new generation. S9 (health re-sync)
    /// and S10 (reminders) register theirs; narrative validation is built in.
    func registerPostRestoreHook(_ hook: @escaping @Sendable () async -> Void) { hooks.append(hook) }

    func dismissCompletionNote() { completionNote = nil }

    // MARK: Flow state

    func beginRestore(from url: URL) {
        discardPreview()
        phase = .needsPassphrase(url)
    }

    /// Back to nothing: removes any plaintext and closes the flow.
    func cancel() {
        guard phase != .restoring, phase != .undoing else { return }
        discardPreview()
        phase = .idle
    }

    func retry(url: URL) { phase = .needsPassphrase(url) }

    /// UI entry: decrypt and validate `url`, then move to `.ready` or `.failed`.
    func openFile(_ url: URL, passphrase: String) async {
        phase = .preparing
        do {
            preview = try await prepare(
                from: EncryptedFileSource(url: url, passphrase: passphrase), passphrase: passphrase)
            phase = .ready
        } catch {
            phase = .failed(Self.failure(for: error), retry: url)
        }
    }

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

    /// Decrypts into a fresh scratch directory and validates. On failure the scratch directory is removed.
    func prepare(from source: some RestorePayloadSource, passphrase: String) async throws -> RestorePreview {
        let scratch = try ScratchSpace.make()
        do {
            try await source.extract(into: scratch)
            let archive = try await Task.detached(priority: .userInitiated) {
                try ArchiveValidator.validate(directory: scratch)
            }.value
            return RestorePreview(
                archive: archive, scratch: scratch, sourceName: source.displayName, passphrase: passphrase)
        } catch {
            ScratchSpace.remove(scratch)
            throw error
        }
    }

    func prepare(from archiveURL: URL, passphrase: String) async throws -> RestorePreview {
        try await prepare(from: EncryptedFileSource(url: archiveURL, passphrase: passphrase), passphrase: passphrase)
    }

    func discardPreview() {
        ScratchSpace.remove(preview?.scratch)
        preview = nil
    }

    // MARK: Commit

    /// Replaces the whole journal with the previewed archive.
    func commit(_ preview: RestorePreview) async throws {
        try await switchGeneration(to: .archive(preview.archive), fallbackPassphrase: preview.passphrase)
        ScratchSpace.remove(preview.scratch)
        self.preview = nil
        completionNote = Copy.Restore.doneNote(entries: preview.counts.entries)
    }

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
            try await switchGeneration(to: .previous(target), fallbackPassphrase: nil)
        } catch {
            phase = .failed(Self.failure(for: error), retry: nil)
            throw error
        }
        completionNote = Copy.Restore.undoneNote
    }

    // MARK: The swap

    private enum Target {
        case archive(ValidatedArchive)
        case previous(String)
    }

    private func switchGeneration(to target: Target, fallbackPassphrase: String?) async throws {
        guard !isSwapping else { throw RestoreFailure.busy }
        isSwapping = true
        defer { isSwapping = false }
        guard let store = host.store, let attachments = host.attachments, let currentID = host.generationID,
            let currentURL = host.generationURL
        else { throw RestoreFailure.switchFailed }
        let switcher = GenerationSwitcher(paths: paths)
        let priorRecord = RecoveryRecord.load(from: paths)

        // (i) quiesce: pending edits are written, then the store refuses every write.
        await events.flushAllDrafts()
        await attachments.waitForIdle()
        await store.setReadOnly(true)

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
                store: store, switcher: switcher, previousID: currentID, built: built, flipped: flipped,
                priorRecord: priorRecord)
            refreshUndoAvailability()
            if error is RestoreFailure { throw error }
            logger.error("switch failed: \(String(describing: type(of: error)), privacy: .public)")
            throw RestoreFailure.switchFailed
        }

        // (vi) hooks, then validate every restored narrative against its week's input (mismatches purge).
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
        store: JournalStore, switcher: GenerationSwitcher, previousID: String, built: BuiltGeneration?, flipped: Bool,
        priorRecord: RecoveryRecord?
    ) async {
        if flipped { try? switcher.flip(to: previousID) }
        if let built { try? switcher.abandon(built.id) }
        if let priorRecord { try? priorRecord.save(to: paths) } else { RecoveryRecord.clear(from: paths) }
        if paths.currentGenerationID() == previousID { await store.setReadOnly(false) }
    }

    // MARK: Safety copy

    /// A portable export of the current journal into `Device/pre-restore/`, newest three kept. Skipped when the
    /// journal holds nothing worth keeping (a new phone, or a fresh install).
    private func writeSafetyCopy(store: JournalStore, generation: URL, passphrase: String?) async throws {
        let snapshot = try await store.archiveSnapshot()
        let data = snapshot.data
        let hasContent =
            !data.entries.isEmpty || !data.attachments.isEmpty || !data.tags.isEmpty || !data.intentions.isEmpty
            || !data.reviews.isEmpty || !data.workouts.isEmpty || !data.importRecords.isEmpty
        guard hasContent else { return }
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
        default: return .damaged
        }
    }
}
