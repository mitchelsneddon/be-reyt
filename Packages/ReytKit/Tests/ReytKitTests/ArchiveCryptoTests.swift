import AppleArchive
import Foundation
import System
import Testing

@testable import ReytKit

@Suite("Archive encryption")
struct ArchiveCryptoTests {
    private let passphrase = "kettle-lamp-orchard-42"

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "reyt-crypto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Every regular file under `root`: relative path to bytes.
    private func contents(_ root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let base = root.resolvingSymlinksInPath().path + "/"
        let walker = try #require(
            FileManager.default.enumerator(
                at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in walker
        where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            out[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return out
    }

    private func encryptedFixture(_ f: ArchiveFixture, passphrase: String) async throws -> (
        payload: URL, aea: URL, work: URL
    ) {
        let payload = try await f.writePayload()
        let work = try scratch()
        let aea = work.appending(path: "x.aea")
        try ArchiveCrypto.encrypt(directory: payload, to: aea, passphrase: passphrase)
        return (payload, aea, work)
    }

    @Test("encrypt then decrypt returns the same files, and the file is not plaintext")
    func roundTrip() async throws {
        let f = try await ArchiveFixture()
        let (payload, aea, work) = try await encryptedFixture(f, passphrase: passphrase)
        defer { try? FileManager.default.removeItem(at: work) }
        let raw = try Data(contentsOf: aea)
        #expect(raw.count > 1000)
        #expect(raw.range(of: Data("be-reyt-archive".utf8)) == nil)
        #expect(raw.range(of: f.photoBBytes) == nil)

        let out = try scratch()
        defer { try? FileManager.default.removeItem(at: out) }
        try ArchiveCrypto.decrypt(archive: aea, passphrase: passphrase, into: out)
        let original = try contents(payload)
        #expect(try contents(out) == original)
        #expect(original.count == 4)  // manifest, data, two attachments
        // and the validator accepts the extracted result, so the photos are byte-identical
        let validated = try ArchiveValidator.validate(directory: out)
        #expect(validated.data == (try f.rawData()))
    }

    @Test("a short passphrase (8 characters) works and a unicode one round-trips")
    func shortAndUnicode() async throws {
        let f = try await ArchiveFixture()
        for phrase in ["abcd1234", "pässwörd-日本語-🌿"] {
            let (payload, aea, work) = try await encryptedFixture(f, passphrase: phrase)
            defer { try? FileManager.default.removeItem(at: work) }
            let out = try scratch()
            defer { try? FileManager.default.removeItem(at: out) }
            try ArchiveCrypto.decrypt(archive: aea, passphrase: phrase, into: out)
            #expect(try contents(out) == (try contents(payload)))
        }
        let long = String(repeating: "a", count: ArchiveCrypto.maxPassphraseBytes)
        _ = try ArchiveCrypto.enginePassword(for: long)
        #expect(throws: ArchiveCryptoError.passphraseTooLong) { try ArchiveCrypto.enginePassword(for: long + "a") }
    }

    @Test("the wrong passphrase is reported as wrongPassphrase and extracts nothing")
    func wrongPassphrase() async throws {
        let f = try await ArchiveFixture()
        let (_, aea, work) = try await encryptedFixture(f, passphrase: passphrase)
        defer { try? FileManager.default.removeItem(at: work) }
        let out = try scratch()
        defer { try? FileManager.default.removeItem(at: out) }
        #expect(throws: ArchiveCryptoError.wrongPassphrase) {
            try ArchiveCrypto.decrypt(archive: aea, passphrase: "not-the-passphrase-at-all", into: out)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test("a flipped ciphertext byte is an error, never a silent success")
    func tampered() async throws {
        let f = try await ArchiveFixture()
        let (_, aea, work) = try await encryptedFixture(f, passphrase: passphrase)
        defer { try? FileManager.default.removeItem(at: work) }
        let original = try Data(contentsOf: aea)
        for offset in [original.count - 100, original.count / 2, 20] {
            var bytes = original
            bytes[offset] ^= 0xFF
            let copy = work.appending(path: "t-\(offset).aea")
            try bytes.write(to: copy)
            let out = try scratch()
            defer { try? FileManager.default.removeItem(at: out) }
            #expect(throws: ArchiveCryptoError.self) {
                try ArchiveCrypto.decrypt(archive: copy, passphrase: passphrase, into: out)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
        }
    }

    @Test("a file that is not an archive is reported as such")
    func notAnArchive() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "g.aea")
        try Data("this is just text".utf8).write(to: file)
        #expect(throws: ArchiveCryptoError.notEncryptedArchive) {
            try ArchiveCrypto.decrypt(archive: file, passphrase: passphrase, into: work.appending(path: "o"))
        }
    }

    // MARK: Hostile archives

    private enum Entry {
        case file(path: String, bytes: String)
        case directory(path: String)
        case symlink(path: String, target: String)
    }

    /// Builds an encrypted archive by hand, so it can contain entries `writeDirectoryContents` never would.
    private func craft(_ entries: [Entry], at url: URL) throws {
        let file = try #require(
            ArchiveByteStream.fileStream(
                path: FilePath(url.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)))
        let context = ArchiveEncryptionContext(
            profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm: .lzfse)
        try context.setPassword(try ArchiveCrypto.enginePassword(for: passphrase))
        let encrypted = try #require(ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: context))
        let stream = try #require(ArchiveStream.encodeStream(writingTo: encrypted))
        for entry in entries {
            let header = ArchiveHeader()
            var blob: Data?
            switch entry {
            case .file(let path, let bytes):
                header.append(
                    .uint(
                        key: ArchiveHeader.FieldKey("TYP"), value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue))
                )
                header.append(.string(key: ArchiveHeader.FieldKey("PAT"), value: path))
                header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o644))
                blob = Data(bytes.utf8)
                header.append(.blob(key: ArchiveHeader.FieldKey("DAT"), size: UInt64(blob?.count ?? 0), offset: 0))
            case .directory(let path):
                header.append(
                    .uint(key: ArchiveHeader.FieldKey("TYP"), value: UInt64(ArchiveHeader.EntryType.directory.rawValue))
                )
                header.append(.string(key: ArchiveHeader.FieldKey("PAT"), value: path))
                header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o755))
            case .symlink(let path, let target):
                header.append(
                    .uint(key: ArchiveHeader.FieldKey("TYP"), value: UInt64(ArchiveHeader.EntryType.link.rawValue)))
                header.append(.string(key: ArchiveHeader.FieldKey("PAT"), value: path))
                header.append(.string(key: ArchiveHeader.FieldKey("LNK"), value: target))
            }
            try stream.writeHeader(header)
            if let blob {
                try blob.withUnsafeBytes { try stream.writeBlob(key: ArchiveHeader.FieldKey("DAT"), from: $0) }
            }
        }
        try stream.close()
        try encrypted.close()
        try file.close()
    }

    @Test("a sanity archive built by hand extracts fine (so the hostile ones fail for the right reason)")
    func craftedControl() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let aea = work.appending(path: "ok.aea")
        try craft([.directory(path: "d"), .file(path: "d/a.txt", bytes: "hello")], at: aea)
        let out = work.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try ArchiveCrypto.decrypt(archive: aea, passphrase: passphrase, into: out)
        #expect(try contents(out) == ["d/a.txt": Data("hello".utf8)])
    }

    @Test("an entry whose path climbs out with ../ is rejected and nothing is written outside")
    func dotDotPath() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let aea = work.appending(path: "evil.aea")
        try craft([.file(path: "../escaped.txt", bytes: "pwned")], at: aea)
        let out = work.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Rejected either by our filter (unsafeEntry) or by the engine itself (corrupted); both are refusals.
        #expect(throws: ArchiveCryptoError.self) {
            try ArchiveCrypto.decrypt(archive: aea, passphrase: passphrase, into: out)
        }
        #expect(!FileManager.default.fileExists(atPath: work.appending(path: "escaped.txt").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test("an absolute path entry is rejected")
    func absolutePath() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let target = work.appending(path: "abs-target.txt")
        let aea = work.appending(path: "evil.aea")
        try craft([.file(path: target.path, bytes: "pwned")], at: aea)
        let out = work.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(throws: ArchiveCryptoError.self) {
            try ArchiveCrypto.decrypt(archive: aea, passphrase: passphrase, into: out)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("a symlink entry is rejected")
    func symlinkEntry() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let aea = work.appending(path: "evil.aea")
        try craft([.symlink(path: "link", target: "/etc")], at: aea)
        let out = work.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(throws: ArchiveCryptoError.self) {
            try ArchiveCrypto.decrypt(archive: aea, passphrase: passphrase, into: out)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test("nothing is written through a symlink planted earlier in the archive")
    func writeThroughSymlink() throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let outside = work.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let aea = work.appending(path: "evil.aea")
        try craft([.symlink(path: "sub", target: outside.path), .file(path: "sub/pwned.txt", bytes: "pwned")], at: aea)
        let out = work.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(throws: ArchiveCryptoError.self) {
            try ArchiveCrypto.decrypt(archive: aea, passphrase: passphrase, into: out)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("export file names follow the documented pattern")
    func names() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 in UTC
        let name = ArchiveCrypto.exportFileName(date: date, timeZone: TimeZone(identifier: "UTC")!, token: "AB12cd34")
        #expect(name == "be-reyt-export-2026-09-21-ab12cd34.aea")
        let random = ArchiveCrypto.exportFileName(date: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(random.wholeMatch(of: /be-reyt-export-2026-09-21-[0-9a-f]{8}\.aea/) != nil)
        #expect(
            ArchiveCrypto.preRestoreFileName(date: date, timeZone: TimeZone(identifier: "UTC")!, token: "00000000")
                == "be-reyt-pre-restore-2026-09-21-00000000.aea")
    }
}
