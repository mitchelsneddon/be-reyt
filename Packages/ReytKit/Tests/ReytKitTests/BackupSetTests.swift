import CryptoKit
import Foundation
import SwiftData
import Testing

@testable import ReytKit

@Suite("Backup blobs and snapshots")
struct BackupSetTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "reyt-blob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let key = Data((0..<32).map { UInt8($0 &+ 1) })

    @Test("a blob round-trips with the right key, is not plaintext, and a wrong key fails")
    func blobRoundTrip() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = Data((0..<(2 * 1024 * 1024 + 5)).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 3) })
        let source = dir.appending(path: "photo.heic")
        try plain.write(to: source)
        let blob = dir.appending(path: "blob.aea")
        try ArchiveCrypto.encryptBlob(source: source, to: blob, dataKey: key)
        let raw = try Data(contentsOf: blob)
        #expect(raw.range(of: plain.prefix(64)) == nil)

        let out = dir.appending(path: "out.heic")
        let result = try ArchiveCrypto.decryptBlob(blob, dataKey: key, to: out)
        #expect(try Data(contentsOf: out) == plain)
        #expect(result.bytes == plain.count)
        #expect(result.sha256 == SHA256.hash(data: plain).map { String(format: "%02x", $0) }.joined())

        let wrong = Data(repeating: 9, count: 32)
        #expect(throws: ArchiveCryptoError.self) {
            try ArchiveCrypto.decryptBlob(blob, dataKey: wrong, to: dir.appending(path: "bad"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "bad").path))
    }

    @Test("a flipped byte in a blob fails instead of decrypting to different bytes")
    func tamperedBlob() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "p.jpg")
        try Data(repeating: 7, count: 100_000).write(to: source)
        let blob = dir.appending(path: "b.aea")
        try ArchiveCrypto.encryptBlob(source: source, to: blob, dataKey: key)
        var raw = try Data(contentsOf: blob)
        raw[raw.count - 40] ^= 0xff
        try raw.write(to: blob)
        #expect(throws: ArchiveCryptoError.self) { try ArchiveCrypto.decryptBlob(blob, dataKey: key) }
    }

    @Test("a snapshot with blobs: encrypt, decrypt, stage blobs, validate, build a generation equal to the original")
    func endToEnd() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }

        // 1. the snapshot payload (no attachments) with blob names and the data key
        let payload = work.appending(path: "payload")
        let lineage = UUID()
        let manifest = try await ArchiveWriter(paths: f.paths, generation: f.generation).write(
            from: f.store, to: payload,
            options: .init(kind: .snapshot, appVersion: "1.0 (1)", lineageID: lineage, dataKey: key))
        #expect(!FileManager.default.fileExists(atPath: payload.appending(path: "attachments").path))
        #expect(manifest.attachments.count == 2)
        for item in manifest.attachments {
            #expect(item.blob == BlobNaming.name(dataKey: key, plaintextSHA256: item.sha256))
        }

        // 2. one blob per attachment, into a folder laid out like the backup set
        let folder = work.appending(path: "folder")
        for item in manifest.attachments {
            let blob = try #require(item.blob)
            let source = f.attachmentFile(ArchiveNames.attachmentFileName(id: item.id, ext: item.ext))
            let destination = folder.appending(path: try #require(BlobNaming.relativePath(for: blob)))
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ArchiveCrypto.encryptBlob(source: source, to: destination, dataKey: key)
        }

        // 3. snapshot encrypted with the passphrase, then opened again
        let aea = work.appending(path: "snapshot.aea")
        try ArchiveCrypto.encrypt(directory: payload, to: aea, passphrase: "short-pass")
        let opened = work.appending(path: "opened")
        try FileManager.default.createDirectory(at: opened, withIntermediateDirectories: true)
        try ArchiveCrypto.decrypt(archive: aea, passphrase: "short-pass", into: opened)
        #expect(try SnapshotBlobs.readDataKey(in: opened) == key)

        // 4. blobs resolved from the folder, validated like a portable archive
        let read = try ArchiveReader.readManifest(in: opened, maxBytes: 1 << 20)
        try SnapshotBlobs.stage(manifest: read, dataKey: key, into: opened) { name in
            folder.appending(path: try #require(BlobNaming.relativePath(for: name)))
        }
        let validated = try ArchiveValidator.validate(directory: opened, verifyAttachmentFiles: true)

        // 5. the rebuilt generation equals the original, photo bytes included
        let built = try GenerationSwitcher(paths: f.paths).build(from: validated)
        let container = try GenerationSwitcher.openContainer(at: f.paths.store(in: built.directory))
        #expect(try ArchiveData.fetch(from: ModelContext(container)) == (try f.rawData()))
        for item in manifest.attachments {
            let name = ArchiveNames.attachmentFileName(id: item.id, ext: item.ext)
            let rebuilt = try Data(contentsOf: f.paths.attachments(in: built.directory).appending(path: name))
            #expect(rebuilt == (try Data(contentsOf: f.attachmentFile(name))))
        }
    }

    @Test("staging fails when a blob is missing or was made under another key, and never leaves a wrong file")
    func stagingFailures() async throws {
        let f = try await ArchiveFixture()
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let payload = work.appending(path: "payload")
        let manifest = try await ArchiveWriter(paths: f.paths, generation: f.generation).write(
            from: f.store, to: payload,
            options: .init(kind: .snapshot, appVersion: "1", lineageID: UUID(), dataKey: key))
        struct Missing: Error {}
        #expect(throws: (any Error).self) {
            try SnapshotBlobs.stage(manifest: manifest, dataKey: key, into: payload) { _ in throw Missing() }
        }
        let item = try #require(manifest.attachments.first)
        let other = Data(repeating: 5, count: 32)
        let blob = work.appending(path: "b.aea")
        try ArchiveCrypto.encryptBlob(
            source: f.attachmentFile(ArchiveNames.attachmentFileName(id: item.id, ext: item.ext)), to: blob,
            dataKey: other)
        #expect(throws: ArchiveError.self) {
            try SnapshotBlobs.stage(manifest: manifest, dataKey: key, into: payload) { _ in blob }
        }
    }

    @Test("a snapshot leaves out an attachment whose file is gone, and says so")
    func snapshotSkipsMissingFile() async throws {
        let f = try await ArchiveFixture()
        try FileManager.default.removeItem(at: f.attachmentFile("\(f.photoB.uuidString.lowercased()).png"))
        let dir = f.base.appending(path: "snap-missing")
        let manifest = try await ArchiveWriter(paths: f.paths, generation: f.generation).write(
            from: f.store, to: dir, options: .init(kind: .snapshot, appVersion: "1", lineageID: UUID(), dataKey: key))
        #expect(manifest.attachments.count == 1)
        #expect(manifest.warnings == [ArchiveWarning.missingAttachment])
        _ = try ArchiveValidator.validate(directory: dir)
    }
}

@Suite("Backup folder names")
struct BackupFolderNamesTests {
    @Test("a listing is read the same whether an evicted file shows as a placeholder or under its real name")
    func normalizesBothEvictionStyles() {
        #expect(BackupFolderNames.normalized("be-reyt-2026-11-05-ab12cd34.aea") == "be-reyt-2026-11-05-ab12cd34.aea")
        #expect(
            BackupFolderNames.normalized(".be-reyt-2026-11-05-ab12cd34.aea.icloud") == "be-reyt-2026-11-05-ab12cd34.aea"
        )
    }

    @Test("half-written files, hidden files and other files are not backups")
    func ignoresNonBackups() {
        #expect(BackupFolderNames.normalized(".x.aea.1234.partial") == nil)
        #expect(BackupFolderNames.normalized("x.aea.partial") == nil)
        #expect(BackupFolderNames.normalized(".DS_Store") == nil)
        #expect(BackupFolderNames.normalized("notes.txt") == nil)
        #expect(BackupFolderNames.normalized("..icloud") == nil)
    }

    @Test("snapshot names carry the civil day and a lowercase token")
    func snapshotName() throws {
        let day = try #require(DateKey("2026-11-05"))
        #expect(BackupFolderNames.snapshotFileName(day: day, token: "AB12CD34") == "be-reyt-2026-11-05-ab12cd34.aea")
    }
}
