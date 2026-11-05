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
    /// Keys the root view, so a future restore that switches generation rebuilds everything.
    private(set) var generationID: String?
    private(set) var openFailed = false
    /// Set once an open has started, so a second trigger (scene active, unlock) can never open a second container.
    @ObservationIgnored private var isOpening = false

    @ObservationIgnored private let paths: Paths
    @ObservationIgnored private var generationURL: URL?
    @ObservationIgnored private var unlockWatcher: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "container")

    init(base: URL = .applicationSupportDirectory) {
        paths = Paths(base: base)
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

    private func open() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.dataRoot, withIntermediateDirectories: true)
        let id: String
        if fm.fileExists(atPath: paths.currentPointer.path) {
            // An unreadable pointer is a stop, not a reset: never start a fresh generation over existing data.
            guard let existing = paths.currentGenerationID() else { throw ContainerHostError.badPointer }
            id = existing
        } else {
            id = "g1"
            try Data((id + "\n").utf8).write(to: paths.currentPointer, options: .atomic)
        }
        let generation = paths.generation(id)
        try fm.createDirectory(at: generation, withIntermediateDirectories: true)
        let attachments = paths.attachments(in: generation)
        try fm.createDirectory(at: attachments, withIntermediateDirectories: true)
        try Paths.applyCompleteProtection(toDirectory: attachments)

        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: paths.store(in: generation))
        let container = try ModelContainer(
            for: schema, migrationPlan: BeReytMigrationPlan.self, configurations: configuration)
        generationURL = generation
        protect()

        let store = JournalStore(modelContainer: container, clock: AppClock.now)
        #if DEBUG
            Task {
                await DebugSeed.runIfRequested(store)
                DebugSeed.dumpProtectionIfRequested(generation: generation, generationID: id)
                publish(container: container, store: store, generationID: id)
            }
        #else
            publish(container: container, store: store, generationID: id)
        #endif
    }

    private func publish(container: ModelContainer, store: JournalStore, generationID: String) {
        self.container = container
        self.store = store
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
