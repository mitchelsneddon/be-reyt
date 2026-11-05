import Foundation
import SwiftData
import Testing

@testable import ReytKit

@Suite("Generation switcher")
struct GenerationSwitcherTests {
    private func validated(_ f: ArchiveFixture) async throws -> ValidatedArchive {
        try ArchiveValidator.validate(directory: try await f.writePayload())
    }

    private func pointer(_ f: ArchiveFixture) throws -> String {
        try String(contentsOf: f.paths.currentPointer, encoding: .utf8)
    }

    private func dataRootNames(_ f: ArchiveFixture) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: f.paths.dataRoot.path))
    }

    struct Boom: Error {}

    @Test(
        "a failure at any build step leaves current on the old generation and no half-built directory",
        arguments: [
            GenerationSwitcher.Step.directoryCreated, .recordsInserted, .attachmentsCopied, .verified,
        ])
    func buildFailure(step: GenerationSwitcher.Step) async throws {
        let f = try await ArchiveFixture()
        let archive = try await validated(f)
        var switcher = GenerationSwitcher(paths: f.paths)
        switcher.hook = { if $0 == step { throw Boom() } }
        #expect(throws: Boom.self) { try switcher.build(from: archive) }
        #expect(try pointer(f) == "g1")
        #expect(try dataRootNames(f) == ["g1", "current"])
        #expect(try ArchiveData.fetch(from: ModelContext(f.container)) == (try f.rawData()))
        try switcher.abandon("g2")  // removing the half-built id is harmless
    }

    @Test("a real build fault (attachment vanished after validation) fails cleanly")
    func vanishedAttachment() async throws {
        let f = try await ArchiveFixture()
        let archive = try await validated(f)
        try FileManager.default.removeItem(
            at: archive.directory.appending(path: "attachments/\(f.photoA.uuidString.lowercased()).heic"))
        let switcher = GenerationSwitcher(paths: f.paths)
        #expect(throws: ArchiveError.self) { try switcher.build(from: archive) }
        #expect(try pointer(f) == "g1")
        #expect(try dataRootNames(f) == ["g1", "current"])
    }

    @Test("a built but never flipped generation can be abandoned; the current one cannot")
    func abandon() async throws {
        let f = try await ArchiveFixture()
        let switcher = GenerationSwitcher(paths: f.paths)
        let built = try switcher.build(from: try await validated(f))
        #expect(FileManager.default.fileExists(atPath: built.directory.path))
        #expect(try pointer(f) == "g1")  // building never moves the pointer
        try switcher.abandon(built.id)
        #expect(!FileManager.default.fileExists(atPath: built.directory.path))
        #expect(throws: PathError.invalidGenerationID) { try switcher.abandon("g1") }
        #expect(FileManager.default.fileExists(atPath: f.generation.path))
        #expect(throws: PathError.invalidGenerationID) { try switcher.abandon("../g1") }
    }

    @Test("a failure before or during the flip leaves the old pointer intact and no temp file behind")
    func flipFailure() async throws {
        let f = try await ArchiveFixture()
        let built = try GenerationSwitcher(paths: f.paths).build(from: try await validated(f))
        for step in [GenerationSwitcher.Step.beforeFlip, .pointerStaged] {
            var switcher = GenerationSwitcher(paths: f.paths)
            switcher.hook = { if $0 == step { throw Boom() } }
            #expect(throws: Boom.self) { try switcher.flip(to: built.id) }
            #expect(try pointer(f) == "g1")
            #expect(f.paths.currentGenerationID() == "g1")
            #expect(try dataRootNames(f) == ["g1", "g2", "current"])
        }
    }

    @Test("the pointer is replaced from a staged temp file: old value until the swap, then the new one in full")
    func flipIsAtomic() async throws {
        let f = try await ArchiveFixture()
        let built = try GenerationSwitcher(paths: f.paths).build(from: try await validated(f))
        let paths = f.paths
        let observed = Box()
        var switcher = GenerationSwitcher(paths: paths)
        switcher.hook = { step in
            if step == .pointerStaged {
                observed.set(
                    (try? String(contentsOf: paths.currentPointer, encoding: .utf8)) ?? "unreadable",
                    staged: (try? FileManager.default.contentsOfDirectory(atPath: paths.dataRoot.path)) ?? [])
            }
        }
        try switcher.flip(to: built.id)
        #expect(observed.pointer == "g1")
        #expect(observed.staged.contains { $0.hasPrefix(".current-") })
        #expect(try pointer(f) == "g2")
        #expect(f.paths.currentGenerationID() == "g2")
        #expect(try dataRootNames(f) == ["g1", "g2", "current"])
    }

    final class Box: @unchecked Sendable {  // test-only mutable capture, written once on one thread
        private(set) var pointer = ""
        private(set) var staged: [String] = []
        func set(_ p: String, staged s: [String]) {
            pointer = p
            staged = s
        }
    }

    @Test("flip creates the pointer when there is none, and refuses a generation with no store")
    func flipFresh() async throws {
        let f = try await ArchiveFixture()
        let built = try GenerationSwitcher(paths: f.paths).build(from: try await validated(f))
        try FileManager.default.removeItem(at: f.paths.currentPointer)
        let switcher = GenerationSwitcher(paths: f.paths)
        try switcher.flip(to: built.id)
        #expect(try pointer(f) == "g2")
        #expect(throws: ArchiveError.self) { try switcher.flip(to: "g9") }
        #expect(throws: PathError.invalidGenerationID) { try switcher.flip(to: "../g1") }
        #expect(try pointer(f) == "g2")
    }

    @Test("after the flip the old generation is kept, its read-only store rejects writes, the new one is live")
    func flipThenReadOnly() async throws {
        let f = try await ArchiveFixture()
        let raw = try f.rawData()
        let switcher = GenerationSwitcher(paths: f.paths)
        let built = try switcher.build(from: try await validated(f))

        await f.store.setReadOnly(true)  // the coordinator quiesces before the flip
        try switcher.flip(to: built.id)

        let old = f.store
        await #expect(throws: JournalStoreError.readOnly) {
            try await old.updateEntry(ArchiveFixture.entryDay, .text("late write"))
        }
        await #expect(throws: JournalStoreError.readOnly) { try await old.createTag(name: "late") }
        #expect(try pointer(f) == "g2")
        // Old generation untouched and still on disk for recovery.
        #expect(FileManager.default.fileExists(atPath: f.paths.store(in: f.generation).path))
        #expect(try f.rawData() == raw)

        // The new generation holds the restored data and accepts writes through a store bound to it.
        let container = try GenerationSwitcher.openContainer(at: f.paths.store(in: built.directory))
        let fresh = JournalStore(modelContainer: container)
        #expect(try ArchiveData.fetch(from: ModelContext(container)) == raw)
        #expect(try await fresh.updateEntry(ArchiveFixture.entryDay, .text("after restore")).dirty)
        let text = try ModelContext(container).fetch(FetchDescriptor<DailyEntry>()).first {
            $0.dateKey == ArchiveFixture.entryDay.string
        }?.text
        #expect(text == "after restore")
    }

    @Test("generation ids count up from the highest existing one")
    func nextID() async throws {
        let f = try await ArchiveFixture()
        let switcher = GenerationSwitcher(paths: f.paths)
        #expect(switcher.nextGenerationID() == "g2")
        try FileManager.default.createDirectory(at: f.paths.generation("g7"), withIntermediateDirectories: true)
        #expect(switcher.nextGenerationID() == "g8")
        #expect(Paths.isValidGenerationID(switcher.nextGenerationID()))
    }
}

@Suite("Generation sweep")
struct GenerationSweepTests {
    private func names(_ f: ArchiveFixture) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: f.paths.dataRoot.path))
    }

    private func make(_ f: ArchiveFixture, _ ids: [String]) throws {
        for id in ids {
            try FileManager.default.createDirectory(at: f.paths.generation(id), withIntermediateDirectories: true)
        }
    }

    @Test("keeps current, the keep set and a fresh recovery generation; deletes the rest")
    func keepsAndDeletes() async throws {
        let f = try await ArchiveFixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try make(f, ["g2", "g3", "g4", "g5"])
        try RecoveryRecord(generationID: "g3", recordedAt: now.addingTimeInterval(-3 * 86_400)).save(to: f.paths)
        let removed = GenerationSwitcher(paths: f.paths).sweepAbandoned(keep: ["g5"], now: now)
        #expect(removed == ["g2", "g4"])
        #expect(try names(f) == ["g1", "g3", "g5", "current"])
        #expect(f.paths.currentGenerationID() == "g1")
    }

    @Test("a recovery generation older than seven days is deleted and its record cleared")
    func expiredRecovery() async throws {
        let f = try await ArchiveFixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try make(f, ["g2"])
        try RecoveryRecord(generationID: "g2", recordedAt: now.addingTimeInterval(-8 * 86_400)).save(to: f.paths)
        let removed = GenerationSwitcher(paths: f.paths).sweepAbandoned(now: now)
        #expect(removed == ["g2"])
        #expect(try names(f) == ["g1", "current"])
        #expect(RecoveryRecord.load(from: f.paths) == nil)
    }

    @Test("the current generation is never swept even if the recovery record names something else")
    func currentIsSafe() async throws {
        let f = try await ArchiveFixture()
        try RecoveryRecord(generationID: "g9", recordedAt: .now).save(to: f.paths)
        GenerationSwitcher(paths: f.paths).sweepAbandoned()
        #expect(FileManager.default.fileExists(atPath: f.paths.store(in: f.generation).path))
    }

    @Test("a missing or unreadable pointer sweeps nothing")
    func noPointerNoSweep() async throws {
        let f = try await ArchiveFixture()
        try make(f, ["g2"])
        try Data("../../bad".utf8).write(to: f.paths.currentPointer)
        #expect(GenerationSwitcher(paths: f.paths).sweepAbandoned().isEmpty)
        #expect(try names(f) == ["g1", "g2", "current"])
    }

    @Test("a tampered recovery file is ignored")
    func badRecoveryFile() async throws {
        let f = try await ArchiveFixture()
        try FileManager.default.createDirectory(at: f.paths.deviceRoot, withIntermediateDirectories: true)
        try Data(#"{"generationID":"../x","recordedAt":"2026-01-01T00:00:00Z"}"#.utf8).write(to: f.paths.recoveryFile)
        #expect(RecoveryRecord.load(from: f.paths) == nil)
    }
}

@Suite("Delete all data")
struct DeleteAllTests {
    struct Boom: Error {}

    private func names(_ f: ArchiveFixture) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: f.paths.dataRoot.path))
    }

    @Test("a new empty generation becomes current and every old generation directory is gone")
    func deleteAll() async throws {
        let f = try await ArchiveFixture()
        let archive = try ArchiveValidator.validate(directory: try await f.writePayload())
        let switcher = GenerationSwitcher(paths: f.paths)
        let second = try switcher.build(from: archive)  // an extra old generation (e.g. a restore recovery copy)
        try RecoveryRecord(generationID: second.id, recordedAt: .now).save(to: f.paths)

        let empty = try switcher.createEmptyAndFlip()
        let report = switcher.removeAllGenerations(except: empty.id)

        #expect(f.paths.currentGenerationID() == empty.id)
        #expect(try names(f) == ["current", empty.id])
        #expect(report.failed.isEmpty)
        #expect(Set(report.removed) == ["g1", second.id])
        #expect(RecoveryRecord.load(from: f.paths) == nil)
        let fetched = try ArchiveData.fetch(
            from: ModelContext(try GenerationSwitcher.openContainer(at: f.paths.store(in: empty.directory))))
        #expect(fetched.entries.isEmpty && fetched.attachments.isEmpty && fetched.tags.isEmpty)
        #expect(fetched.reviews.isEmpty && fetched.intentions.isEmpty && fetched.workouts.isEmpty)
        #expect(FileManager.default.fileExists(atPath: f.paths.attachments(in: empty.directory).path))
    }

    @Test(
        "a failure before the flip leaves the old journal intact and no new directory",
        arguments: [GenerationSwitcher.Step.directoryCreated, .verified, .beforeFlip, .pointerStaged])
    func failureBeforeFlip(step: GenerationSwitcher.Step) async throws {
        let f = try await ArchiveFixture()
        var switcher = GenerationSwitcher(paths: f.paths)
        switcher.hook = { if $0 == step { throw Boom() } }
        #expect(throws: Boom.self) { try switcher.createEmptyAndFlip() }
        #expect(f.paths.currentGenerationID() == "g1")
        #expect(try names(f) == ["g1", "current"])
        #expect(try ArchiveData.fetch(from: ModelContext(f.container)) == (try f.rawData()))
    }

    @Test("removal refuses to run when the kept id is not the current generation")
    func refusesWhenNotCurrent() async throws {
        let f = try await ArchiveFixture()
        let switcher = GenerationSwitcher(paths: f.paths)
        let report = switcher.removeAllGenerations(except: "g9")
        #expect(report == .init())
        #expect(try names(f) == ["g1", "current"])
    }
}
