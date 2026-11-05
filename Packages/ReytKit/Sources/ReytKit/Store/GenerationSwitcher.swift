import Foundation
import SwiftData

/// A fully built, verified generation that `current` does not point at yet.
public struct BuiltGeneration: Sendable, Equatable {
    public let id: String
    public let directory: URL
}

/// Restore's swap logic. `build` makes a new `Data/{gen}/` from a validated archive without touching the current
/// one; `flip` atomically repoints `Data/current`. The old generation is never deleted here.
///
/// The caller (RestoreCoordinator) sets the old `JournalStore` read-only before `flip`.
public struct GenerationSwitcher: Sendable {
    /// Steps at which a test hook may throw to simulate a crash or failure.
    public enum Step: Sendable, Equatable {
        case directoryCreated, recordsInserted, attachmentsCopied, verified, beforeFlip, pointerStaged
    }

    public let paths: Paths
    var hook: (@Sendable (Step) throws -> Void)?

    public init(paths: Paths) { self.paths = paths }

    /// Opens (creating if needed) the store file of a generation with the app's schema and migration plan.
    public static func openContainer(at storeURL: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL))
    }

    /// `g{n+1}`, where n is the highest number among existing generation directories and the pointer.
    /// A number is never reused while a higher one exists, so a new id never collides with a kept old generation.
    public func nextGenerationID() -> String {
        var highest = 0
        func consider(_ name: String) {
            if name.hasPrefix("g"), let n = Int(name.dropFirst()) { highest = max(highest, n) }
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.dataRoot.path)) ?? []
        names.forEach(consider)
        if let current = paths.currentGenerationID() { consider(current) }
        return "g\(highest + 1)"
    }

    // MARK: Build

    public func build(from archive: ValidatedArchive) throws -> BuiltGeneration {
        let fm = FileManager.default
        let id = nextGenerationID()
        guard Paths.isValidGenerationID(id) else { throw PathError.invalidGenerationID }
        let directory = paths.generation(id)
        try fm.createDirectory(at: paths.dataRoot, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: directory.path) else { throw ArchiveError.destinationNotEmpty }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            try fm.createDirectory(at: paths.attachments(in: directory), withIntermediateDirectories: true)
            try hook?(.directoryCreated)

            try insertRecords(archive.data, into: directory)
            try hook?(.recordsInserted)

            try copyAttachments(archive, into: directory)
            try hook?(.attachmentsCopied)

            try paths.applyCompleteProtection(toGeneration: directory)
            try Paths.applyCompleteProtection(toDirectory: paths.attachments(in: directory))
            try verify(archive, in: directory)
            try hook?(.verified)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
        return BuiltGeneration(id: id, directory: directory)
    }

    /// One transaction: every record is inserted, then a single save. The container is released on return.
    private func insertRecords(_ data: ArchiveData, into directory: URL) throws {
        let container = try Self.openContainer(at: paths.store(in: directory))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        data.insert(into: context)
        try context.save()
    }

    private func copyAttachments(_ archive: ValidatedArchive, into directory: URL) throws {
        let manifestByID = Dictionary(uniqueKeysWithValues: archive.manifest.attachments.map { ($0.id, $0) })
        let source = archive.directory.appending(path: ArchiveNames.attachmentsDir, directoryHint: .isDirectory)
        for a in archive.data.attachments {
            guard let item = manifestByID[a.id] else { throw ArchiveError.attachmentMismatch(a.id.uuidString) }
            let name = ArchiveNames.attachmentFileName(id: a.id, ext: item.ext)
            let from = source.appending(path: name, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: from.path) else { throw ArchiveError.missingFile(name) }
            let to = try paths.resolveAttachment(relativePath: a.relativePath, in: directory)
            let copied = try FileStreaming.copy(from: from, to: to)
            guard copied.sha256 == item.sha256, copied.bytes == item.bytes else {
                throw ArchiveError.checksumMismatch(name)
            }
        }
    }

    /// Re-opens the persisted store and compares it with the archive, so a silent save failure is caught.
    private func verify(_ archive: ValidatedArchive, in directory: URL) throws {
        let container = try Self.openContainer(at: paths.store(in: directory))
        let fetched = try ArchiveData.fetch(from: ModelContext(container))
        guard ArchiveManifest.Counts(fetched) == archive.counts else {
            throw ArchiveError.verificationFailed("record counts differ after the build")
        }
        guard fetched == archive.data else { throw ArchiveError.verificationFailed("records differ after the build") }
        for a in archive.data.attachments {
            let file = try paths.resolveAttachment(relativePath: a.relativePath, in: directory)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw ArchiveError.verificationFailed("attachment file missing after the build")
            }
        }
    }

    // MARK: Delete all data

    /// What `removeAllGenerations` could and could not delete.
    public struct RemovalReport: Sendable, Equatable {
        public var removed: [String] = []
        public var failed: [String] = []
    }

    /// Makes a new, empty, verified generation beside the current one without touching the pointer.
    public func createEmpty() throws -> BuiltGeneration {
        let fm = FileManager.default
        let id = nextGenerationID()
        guard Paths.isValidGenerationID(id) else { throw PathError.invalidGenerationID }
        let directory = paths.generation(id)
        try fm.createDirectory(at: paths.dataRoot, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: directory.path) else { throw ArchiveError.destinationNotEmpty }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            try fm.createDirectory(at: paths.attachments(in: directory), withIntermediateDirectories: true)
            try hook?(.directoryCreated)
            let container = try Self.openContainer(at: paths.store(in: directory))
            let context = ModelContext(container)
            try context.save()
            try paths.applyCompleteProtection(toGeneration: directory)
            try Paths.applyCompleteProtection(toDirectory: paths.attachments(in: directory))
            try hook?(.verified)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
        return BuiltGeneration(id: id, directory: directory)
    }

    /// Delete-all, step one: creates an empty generation and points `current` at it. On any failure the new
    /// directory is removed and the pointer is left as it was, so the old journal is untouched.
    public func createEmptyAndFlip() throws -> BuiltGeneration {
        let built = try createEmpty()
        do {
            try flip(to: built.id)
        } catch {
            try? abandon(built.id)
            throw error
        }
        return built
    }

    /// Delete-all, step two: removes every generation directory except `keep`, plus the restore-recovery record
    /// and any staged pointer files. Deliberately ignores the recovery window: this is a deliberate delete.
    /// Does nothing unless `keep` is the current generation, so it can never delete the live journal.
    public func removeAllGenerations(except keep: String) -> RemovalReport {
        var report = RemovalReport()
        guard paths.currentGenerationID() == keep else { return report }
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: paths.dataRoot.path)) ?? [] {
            if name.hasPrefix(".current-") {
                try? fm.removeItem(at: paths.dataRoot.appending(path: name))
                continue
            }
            guard Paths.isValidGenerationID(name), name != keep, name != "current" else { continue }
            do {
                try fm.removeItem(at: paths.generation(name))
                report.removed.append(name)
            } catch {
                report.failed.append(name)
            }
        }
        RecoveryRecord.clear(from: paths)
        report.removed.sort()
        report.failed.sort()
        return report
    }

    // MARK: Flip

    /// Atomically points `Data/current` at `id`: the new value is staged in a temp file next to the pointer, then
    /// swapped in with `replaceItemAt` (a rename), so the pointer is always either the old or the new id in full.
    public func flip(to id: String) throws {
        guard Paths.isValidGenerationID(id) else { throw PathError.invalidGenerationID }
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.store(in: paths.generation(id)).path) else {
            throw ArchiveError.missingFile("Data/\(id)/store.sqlite")
        }
        try hook?(.beforeFlip)
        try fm.createDirectory(at: paths.dataRoot, withIntermediateDirectories: true)
        let staged = paths.dataRoot.appending(path: ".current-\(UUID().uuidString)", directoryHint: .notDirectory)
        do {
            try Data(id.utf8).write(to: staged)
            try hook?(.pointerStaged)
            if fm.fileExists(atPath: paths.currentPointer.path) {
                _ = try fm.replaceItemAt(paths.currentPointer, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: paths.currentPointer)
            }
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }

    /// Deletes a generation that was built but never flipped to. Refuses the current generation.
    public func abandon(_ id: String) throws {
        guard Paths.isValidGenerationID(id) else { throw PathError.invalidGenerationID }
        guard paths.currentGenerationID() != id else { throw PathError.invalidGenerationID }
        try? FileManager.default.removeItem(at: paths.generation(id))
    }

    /// Deletes generation directories that are neither current, in `keep`, nor the restore-recovery generation
    /// (while that is within its seven days; an expired record is cleared). Returns the ids removed.
    /// Does nothing when the pointer is missing or unreadable, so a damaged pointer can never lead to a wipe.
    @discardableResult
    public func sweepAbandoned(keep: Set<String> = [], now: Date = Date.now) -> [String] {
        guard let current = paths.currentGenerationID() else { return [] }
        var protected = keep.union([current])
        if let record = RecoveryRecord.load(from: paths) {
            if record.isAvailable(now: now) {
                protected.insert(record.generationID)
            } else {
                RecoveryRecord.clear(from: paths)
            }
        }
        let fm = FileManager.default
        var removed: [String] = []
        for name in (try? fm.contentsOfDirectory(atPath: paths.dataRoot.path)) ?? [] {
            guard Paths.isValidGenerationID(name), !protected.contains(name) else { continue }
            var isDirectory: ObjCBool = false
            let url = paths.generation(name)
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if (try? fm.removeItem(at: url)) != nil { removed.append(name) }
        }
        return removed.sorted()
    }
}
