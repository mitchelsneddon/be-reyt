import Foundation
import OSLog
import Observation
import ReytKit

/// Delete all data. The order is what makes a failure safe:
/// 1. quiesce (drafts written, photo imports settled, store read-only);
/// 2. make a fresh empty generation and flip `current` to it, then reopen the container;
///    any failure up to here puts everything back, so the old journal is untouched;
/// 3. delete every other generation (no recovery copy is kept), cached thumbnails and scratch files;
/// 4. run every registered device wiper.
/// Failures in 3 and 4 happen after the journal is already empty, so they are reported, not rolled back.
@MainActor @Observable
final class DeleteAllCoordinator {
    enum Phase: Equatable { case idle, working, failed }

    private(set) var phase: Phase = .idle
    /// One calm line shown after the app rebuilt, until dismissed.
    private(set) var completionNote: String?

    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let backup: BackupManager
    @ObservationIgnored private let registry: DeviceDataRegistry
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "delete-all")

    init(host: ContainerHost, events: JournalEvents, backup: BackupManager, registry: DeviceDataRegistry) {
        self.host = host
        self.events = events
        self.backup = backup
        self.registry = registry
    }

    func dismissCompletionNote() { completionNote = nil }
    func resetFailure() { if phase == .failed { phase = .idle } }

    func deleteAll() async {
        guard phase != .working else { return }
        guard let store = host.store, let attachments = host.attachments, let previousID = host.generationID else {
            phase = .failed
            return
        }
        phase = .working
        completionNote = nil
        let paths = host.paths
        let switcher = GenerationSwitcher(paths: paths)

        // (1) quiesce, as restore does.
        await events.flushAllDrafts()
        await attachments.waitForIdle()
        await store.setReadOnly(true)
        await backup.quiesce()

        // (2) empty generation, flip, reopen.
        var built: BuiltGeneration?
        do {
            let generation = try await Task.detached(priority: .userInitiated) {
                try switcher.createEmptyAndFlip()
            }.value
            built = generation
            try host.reopenCurrent()
        } catch {
            logger.error("delete all failed: \(String(describing: type(of: error)), privacy: .public)")
            if let built {
                try? switcher.flip(to: previousID)
                try? switcher.abandon(built.id)
            }
            if paths.currentGenerationID() == previousID { await store.setReadOnly(false) }
            backup.resumeAfterQuiesce()
            phase = .failed
            return
        }
        guard let built else { return }

        // (3) everything else on disk.
        var leftovers: [String] = []
        let report = await Task.detached(priority: .userInitiated) { switcher.removeAllGenerations(except: built.id) }
            .value
        if !report.failed.isEmpty { leftovers.append(Copy.DeleteAll.leftoverOldData) }
        let thumbnails = URL.cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: thumbnails.path),
            (try? FileManager.default.removeItem(at: thumbnails)) == nil
        {
            leftovers.append(Copy.DeleteAll.leftoverCaches)
        }
        ScratchSpace.clearAll()

        // (4) device-local state.
        leftovers += await registry.wipeAll()

        completionNote = leftovers.isEmpty ? Copy.DeleteAll.done : Copy.DeleteAll.partial(leftovers)
        phase = .idle
    }
}
