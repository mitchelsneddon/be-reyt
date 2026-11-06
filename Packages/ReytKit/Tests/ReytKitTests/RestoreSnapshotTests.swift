import Foundation
import SwiftData
import Testing

@testable import ReytKit

/// Restoring from the backup set: snapshot + blobs back into a validated payload, and what the lineage and
/// retention rules do around a restore.
@Suite("Restore from a backup snapshot")
struct RestoreSnapshotTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "reyt-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A backup folder holding one snapshot and its blobs, written the way a backup run does.
    private struct BackupSet {
        let folder: URL
        let snapshot: URL
        let manifest: ArchiveManifest
    }

    private func makeSet(_ f: ArchiveFixture, in work: URL, passphrase: String, key: Data) async throws -> BackupSet {
        let payload = work.appending(path: "payload-\(UUID().uuidString)")
        let manifest = try await ArchiveWriter(paths: f.paths, generation: f.generation).write(
            from: f.store, to: payload,
            options: .init(kind: .snapshot, appVersion: "1.0 (1)", lineageID: UUID(), dataKey: key))
        let folder = work.appending(path: "folder-\(UUID().uuidString)")
        for item in manifest.attachments {
            let blob = try #require(item.blob)
            let destination = folder.appending(path: try #require(BlobNaming.relativePath(for: blob)))
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ArchiveCrypto.encryptBlob(
                source: f.attachmentFile(ArchiveNames.attachmentFileName(id: item.id, ext: item.ext)), to: destination,
                dataKey: key)
        }
        let snapshot = folder.appending(path: "snapshots/be-reyt-2026-11-05-ab12cd34.aea")
        try ArchiveCrypto.encrypt(directory: payload, to: snapshot, passphrase: passphrase)
        return BackupSet(folder: folder, snapshot: snapshot, manifest: manifest)
    }

    /// The restore's prepare steps, as `SnapshotSource` runs them.
    private func open(_ set: BackupSet, passphrase: String, in work: URL) throws -> (ValidatedArchive, Data) {
        let opened = work.appending(path: "opened-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: opened, withIntermediateDirectories: true)
        try ArchiveCrypto.decrypt(archive: set.snapshot, passphrase: passphrase, into: opened)
        let manifest = try ArchiveReader.readManifest(in: opened, maxBytes: 1 << 20)
        let key = try SnapshotBlobs.readDataKey(in: opened)
        try SnapshotBlobs.stage(manifest: manifest, dataKey: key, into: opened) { name in
            set.folder.appending(path: try #require(BlobNaming.relativePath(for: name)))
        }
        return (try ArchiveValidator.validate(directory: opened, verifyAttachmentFiles: true), key)
    }

    @Test("a snapshot whose blobs are present restores to an identical journal, photo bytes included")
    func identicalJournal() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let set = try await makeSet(f, in: work, passphrase: "a-passphrase", key: Data(repeating: 3, count: 32))
        let (validated, _) = try open(set, passphrase: "a-passphrase", in: work)
        let built = try GenerationSwitcher(paths: f.paths).build(from: validated)
        let container = try GenerationSwitcher.openContainer(at: f.paths.store(in: built.directory))
        #expect(try ArchiveData.fetch(from: ModelContext(container)) == (try f.rawData()))
        for item in set.manifest.attachments {
            let name = ArchiveNames.attachmentFileName(id: item.id, ext: item.ext)
            #expect(
                try Data(contentsOf: f.paths.attachments(in: built.directory).appending(path: name))
                    == (try Data(contentsOf: f.attachmentFile(name))))
        }
    }

    @Test("a corrupt or missing blob fails the preparation, so no generation is built and the pointer never moves")
    func corruptBlobStopsEverything() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let set = try await makeSet(f, in: work, passphrase: "a-passphrase", key: Data(repeating: 3, count: 32))
        let before = f.paths.currentGenerationID()
        let dataRoot = f.paths.dataRoot
        let generationsBefore = try FileManager.default.contentsOfDirectory(atPath: dataRoot.path).sorted()

        // one blob damaged
        let blob = try #require(set.manifest.attachments.first?.blob)
        let file = set.folder.appending(path: try #require(BlobNaming.relativePath(for: blob)))
        var raw = try Data(contentsOf: file)
        raw[raw.count / 2] ^= 0xff
        try raw.write(to: file)
        #expect(throws: (any Error).self) { try open(set, passphrase: "a-passphrase", in: work) }

        // another blob gone
        try FileManager.default.removeItem(at: file)
        #expect(throws: (any Error).self) { try open(set, passphrase: "a-passphrase", in: work) }

        #expect(f.paths.currentGenerationID() == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dataRoot.path).sorted() == generationsBefore)
    }

    @Test("a blob that decrypts to different bytes than the manifest promised fails the preparation")
    func wrongContentBlob() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let key = Data(repeating: 3, count: 32)
        let set = try await makeSet(f, in: work, passphrase: "a-passphrase", key: key)
        let item = try #require(set.manifest.attachments.first)
        let blobName = try #require(item.blob)
        let file = set.folder.appending(path: try #require(BlobNaming.relativePath(for: blobName)))
        let other = work.appending(path: "other.bin")
        try Data("not the photo".utf8).write(to: other)
        try FileManager.default.removeItem(at: file)
        try ArchiveCrypto.encryptBlob(source: other, to: file, dataKey: key)
        #expect(throws: ArchiveError.self) { try open(set, passphrase: "a-passphrase", in: work) }
    }

    @Test("a snapshot made under an older passphrase opens only with that passphrase")
    func olderPassphrase() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let set = try await makeSet(f, in: work, passphrase: "the old passphrase", key: Data(repeating: 3, count: 32))
        #expect(throws: ArchiveCryptoError.wrongPassphrase) {
            try open(set, passphrase: "the new passphrase", in: work)
        }
        let (validated, _) = try open(set, passphrase: "the old passphrase", in: work)
        #expect(validated.counts.entries == set.manifest.counts.entries)
    }

    @Test("a snapshot from another phone restores with its own data key, whatever key this phone holds")
    func otherPhonesKey() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let theirs = Data((0..<32).map { UInt8($0 &* 7 &+ 1) })
        let set = try await makeSet(f, in: work, passphrase: "shared passphrase", key: theirs)
        let (validated, key) = try open(set, passphrase: "shared passphrase", in: work)
        #expect(key == theirs)  // what the app adopts when this phone has none, and ignores when it has one
        #expect(validated.counts.attachments == set.manifest.attachments.count)
        let built = try GenerationSwitcher(paths: f.paths).build(from: validated)
        let container = try GenerationSwitcher.openContainer(at: f.paths.store(in: built.directory))
        #expect(try ArchiveData.fetch(from: ModelContext(container)) == (try f.rawData()))
    }

    // MARK: Lineage and retention around a restore

    private let today = DateKey("2026-11-05")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("after a restore the new lineage's same-day snapshot never replaces the old lineage's one")
    func newLineageKeepsOldSameDay() {
        let oldLineage = UUID()
        let newLineage = UUID()
        let restored = KnownSnapshot(
            name: "be-reyt-2026-11-05-aaaaaaaa.aea", dayKey: today, lineageID: oldLineage, verified: true,
            createdAt: now.addingTimeInterval(-3600), referencedBlobNames: ["b1"])
        // due: nothing of today in the new lineage yet, however fresh the old lineage's snapshot is
        #expect(
            BackupPlan.isDue(dirty: true, today: today, lineageID: newLineage, snapshots: [restored], now: now))
        #expect(BackupPlan.replacementTargets(today: today, lineageID: newLineage, snapshots: [restored]).isEmpty)

        let fresh = KnownSnapshot(
            name: "be-reyt-2026-11-05-bbbbbbbb.aea", dayKey: today, lineageID: newLineage, verified: true,
            createdAt: now, referencedBlobNames: ["b2"])
        let result = BackupPlan.cleanup(
            runVerified: true, newSnapshot: fresh.name, snapshots: [restored, fresh],
            folderSnapshotNames: [restored.name, fresh.name], folderBlobNames: ["b1", "b2"], now: now)
        #expect(result.snapshotsToDelete.isEmpty)
        #expect(Set(result.kept) == [restored.name, fresh.name])
        #expect(result.blobsToDelete.isEmpty)  // the restored snapshot's blobs are known, so they are still held
    }

    @Test("the safety copy before a restore survives pruning for 30 days and its photos are held")
    func preRestoreSurvives() {
        let dailies = (0..<31).map { days in
            KnownSnapshot(
                name: "d\(days)", dayKey: today.adding(days: -days), lineageID: UUID(), verified: true,
                createdAt: now.addingTimeInterval(-Double(days) * 86_400), referencedBlobNames: [])
        }
        let safety = KnownSnapshot(
            name: "be-reyt-pre-restore-2026-10-10-cccccccc.aea", dayKey: today.adding(days: -26),
            lineageID: UUID(), kind: .preRestore, verified: true,
            createdAt: now.addingTimeInterval(-26 * 86_400), referencedBlobNames: ["only-in-safety-copy"])
        let all = dailies + [safety]
        let result = BackupPlan.cleanup(
            runVerified: true, newSnapshot: "d0", snapshots: all, folderSnapshotNames: Set(all.map(\.name)),
            folderBlobNames: ["only-in-safety-copy"], now: now)
        #expect(result.snapshotsToDelete == ["d30"])
        #expect(result.kept.contains(safety.name))
        #expect(result.blobsToDelete.isEmpty)
    }

    @Test("file names say their day and kind; exports and strangers are not snapshots")
    func snapshotInfo() throws {
        let daily = try #require(BackupFolderNames.snapshotInfo(fileName: "be-reyt-2026-11-05-ab12cd34.aea"))
        #expect(daily.day == DateKey("2026-11-05") && daily.kind == .daily)
        let pre = try #require(BackupFolderNames.snapshotInfo(fileName: "be-reyt-pre-restore-2026-11-04-ab12cd34.aea"))
        #expect(pre.day == DateKey("2026-11-04") && pre.kind == .preRestore)
        #expect(BackupFolderNames.snapshotInfo(fileName: "be-reyt-export-2026-11-05-ab12cd34.aea") == nil)
        #expect(BackupFolderNames.snapshotInfo(fileName: "notes.aea") == nil)
        #expect(BackupFolderNames.snapshotInfo(fileName: "be-reyt-2026-13-05-ab12cd34.aea") == nil)
        let day = try #require(DateKey("2026-11-05"))
        #expect(
            BackupFolderNames.preRestoreFileName(day: day, token: "AB12CD34")
                == "be-reyt-pre-restore-2026-11-05-ab12cd34.aea")
    }
}
