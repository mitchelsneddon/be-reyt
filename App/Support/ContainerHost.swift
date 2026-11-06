import Foundation
import OSLog
import Observation
import ReytKit
import SwiftData
import UIKit

/// Owns the `ModelContainer` and `JournalStore`. The container is created lazily, only once protected data is
/// available, so a launch while the phone is locked never opens SQLite (plan req 25).
@MainActor @Observable
final class ContainerHost {
    private(set) var container: ModelContainer?
    private(set) var store: JournalStore?
    private(set) var attachments: AttachmentStore?
    /// Keys the root view, so a future restore that switches generation rebuilds everything.
    private(set) var generationID: String?
    private(set) var openFailed = false
    /// Set once an open has started, so a second trigger (scene active, unlock) can never open a second container.
    @ObservationIgnored private var isOpening = false

    @ObservationIgnored let paths: Paths
    @ObservationIgnored private(set) var generationURL: URL?
    @ObservationIgnored private var unlockWatcher: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "container")

    init(base: URL = .applicationSupportDirectory) {
        paths = Paths(base: base)
        #if DEBUG
            // Simulator-only: `-wipeData` starts from an empty app (all generations and device state).
            if CommandLine.arguments.contains("-wipeData") {
                try? FileManager.default.removeItem(at: paths.dataRoot)
                try? FileManager.default.removeItem(at: paths.deviceRoot)
            }
        #endif
        ScratchSpace.clearAll()
        openIfPossible()
    }

    func openIfPossible() {
        guard container == nil, !openFailed, !isOpening else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            watchForUnlock()
            return
        }
        isOpening = true
        do {
            try open()
        } catch {
            isOpening = false
            logger.error("open failed: \(String(describing: type(of: error)), privacy: .public)")
            openFailed = true
        }
    }

    /// Re-applies complete protection to the generation directory, store, `-wal` and `-shm`.
    /// Called after opening and whenever the scene goes to the background.
    func protect() {
        guard let generationURL else { return }
        do {
            try paths.applyCompleteProtection(toGeneration: generationURL)
        } catch {
            logger.error("protection failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Everything needed to show one generation.
    private struct Opened {
        let container: ModelContainer
        let store: JournalStore
        let attachments: AttachmentStore
        let generationID: String
        let generation: URL
    }

    /// Opens whatever `Data/current` points at (creating `g1` on a first run).
    private func build() throws -> Opened {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.dataRoot, withIntermediateDirectories: true)
        let id: String
        // A bad or missing pointer beside real data is a stop, not a reset: never start a fresh generation over it.
        switch paths.resolveLaunchGeneration() {
        case .badPointer: throw ContainerHostError.badPointer
        case .open(let existing): id = existing
        case .firstRun:
            id = "g1"
            try Data((id + "\n").utf8).write(to: paths.currentPointer, options: .atomic)
        }
        let generation = paths.generation(id)
        try fm.createDirectory(at: generation, withIntermediateDirectories: true)
        let attachmentsDirectory = paths.attachments(in: generation)
        try fm.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try Paths.applyCompleteProtection(toDirectory: attachmentsDirectory)

        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: paths.store(in: generation))
        let container = try ModelContainer(
            for: schema, migrationPlan: BeReytMigrationPlan.self, configurations: configuration)
        let store = JournalStore(modelContainer: container, clock: AppClock.now)
        let attachments = AttachmentStore(store: store, paths: paths, generation: generation, generationID: id)
        return Opened(
            container: container, store: store, attachments: attachments, generationID: id, generation: generation)
    }

    private func open() throws {
        let opened = try build()
        let (container, store, attachments, id, generation) = (
            opened.container, opened.store, opened.attachments, opened.generationID, opened.generation
        )
        generationURL = generation
        protect()
        let paths = self.paths
        #if DEBUG
            Task {
                await attachments.sweepOrphans()
                await DebugSeed.runIfRequested(store, attachments: attachments)
                DebugSeed.dumpProtectionIfRequested(generation: generation, generationID: id)
                publish(container: container, store: store, attachments: attachments, generationID: id)
                GenerationSwitcher(paths: paths).sweepAbandoned()
            }
        #else
            publish(container: container, store: store, attachments: attachments, generationID: id)
            Task {
                await attachments.sweepOrphans()
                GenerationSwitcher(paths: paths).sweepAbandoned()
            }
        #endif
    }

    /// Re-opens at the generation `Data/current` now names. Called by restore after the pointer flips: publishing a
    /// new `generationID` rebuilds the root view, and with it the container, store and every model.
    func reopenCurrent() throws {
        let opened = try build()
        generationURL = opened.generation
        protect()
        publish(
            container: opened.container, store: opened.store, attachments: opened.attachments,
            generationID: opened.generationID)
        let attachments = opened.attachments
        Task { await attachments.sweepOrphans() }
    }

    private func publish(
        container: ModelContainer, store: JournalStore, attachments: AttachmentStore, generationID: String
    ) {
        self.container = container
        self.store = store
        self.attachments = attachments
        self.generationID = generationID
        unlockWatcher?.cancel()
        unlockWatcher = nil
    }

    private func watchForUnlock() {
        guard unlockWatcher == nil else { return }
        unlockWatcher = Task { [weak self] in
            let name = UIApplication.protectedDataDidBecomeAvailableNotification
            for await _ in NotificationCenter.default.notifications(named: name) {
                guard let self else { return }
                self.unlockWatcher = nil
                self.openIfPossible()
                return
            }
        }
    }
}

enum ContainerHostError: Error { case badPointer }
