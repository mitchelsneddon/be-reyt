import AppleArchive
import Foundation
import System

public enum ArchiveCryptoError: Error, Equatable, Sendable {
    /// The passphrase did not open the file (or the file's header is damaged: the format cannot tell them apart).
    case wrongPassphrase
    /// The file is not an encrypted archive.
    case notEncryptedArchive
    /// The file opened but its contents failed authentication or could not be read to the end.
    case corrupted
    /// An entry's path escapes the destination, or an entry is a symlink or other non-regular file.
    case unsafeEntry(String)
    case passphraseTooLong
    case io(String)
}

/// Passphrase-encrypted single-file archives (AppleArchive, scrypt profile). Streaming: memory stays flat however
/// large the photo library is. Platform-only crypto, nothing hand-rolled; the Mac's `aea` tool can open the files.
public enum ArchiveCrypto {
    public static let maxPassphraseBytes = 256

    /// AppleArchive refuses passwords under 20 bytes. A short passphrase gets this fixed suffix so the app can keep
    /// its own minimum at 8 characters. Documented for disaster recovery with `aea`: password = passphrase + suffix.
    static let shortPassphraseSuffix = " | be reyt backup"
    static let minimumEngineBytes = 20

    /// The exact password handed to the engine.
    public static func enginePassword(for passphrase: String) throws -> String {
        let bytes = passphrase.utf8.count
        guard bytes <= maxPassphraseBytes else { throw ArchiveCryptoError.passphraseTooLong }
        return bytes < minimumEngineBytes ? passphrase + shortPassphraseSuffix : passphrase
    }

    private static func filePath(_ url: URL) -> FilePath { FilePath(url.path) }

    // MARK: Names and scratch space

    /// `be-reyt-export-{YYYY-MM-DD}-{8 hex}.aea`, the date in the given time zone.
    public static func exportFileName(
        date: Date = Date.now, timeZone: TimeZone = .current, token: String = String(UUID().uuidString.prefix(8))
    ) -> String {
        "be-reyt-export-\(isoDay(date, timeZone))-\(token.lowercased()).aea"
    }

    /// `be-reyt-pre-restore-{YYYY-MM-DD}-{8 hex}.aea`.
    public static func preRestoreFileName(
        date: Date = Date.now, timeZone: TimeZone = .current, token: String = String(UUID().uuidString.prefix(8))
    ) -> String {
        "be-reyt-pre-restore-\(isoDay(date, timeZone))-\(token.lowercased()).aea"
    }

    private static func isoDay(_ date: Date, _ timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// A fresh empty directory under `parent`, protected `.completeUnlessOpen` on iOS. Callers delete it in `defer`.
    public static func makeScratchDirectory(in parent: URL) throws -> URL {
        let directory = parent.appending(path: "scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        protectUnlessOpen(directory)
        return directory
    }

    static func protectUnlessOpen(_ url: URL) {
        #if os(iOS)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        #endif
    }

    // MARK: Encrypt

    /// Packs `directory` into one encrypted file at `destination`. Written to a sibling temp file, then moved, so a
    /// failure or interruption never leaves a partial file at `destination`.
    public static func encrypt(directory: URL, to destination: URL, passphrase: String) throws {
        let password = try enginePassword(for: passphrase)
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent()
            .appending(
                path: ".\(destination.lastPathComponent).\(UUID().uuidString).partial", directoryHint: .notDirectory)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try writeEncrypted(directory: directory, to: temp, password: password)
            protectUnlessOpen(temp)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: destination)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    private static func writeEncrypted(directory: URL, to file: URL, password: String) throws {
        guard
            let fileStream = ArchiveByteStream.fileStream(
                path: filePath(file), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600))
        else { throw ArchiveCryptoError.io("cannot create the file") }
        let context = ArchiveEncryptionContext(
            profile: .hkdf_sha256_aesctr_hmac__scrypt__none, compressionAlgorithm: .lzfse)
        do { try context.setPassword(password) } catch { throw ArchiveCryptoError.io("cannot set the passphrase") }
        guard let encrypted = ArchiveByteStream.encryptionStream(writingTo: fileStream, encryptionContext: context),
            let archive = ArchiveStream.encodeStream(writingTo: encrypted),
            let keys = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM")
        else {
            try? fileStream.close()
            throw ArchiveCryptoError.io("cannot open the archive stream")
        }
        do {
            try archive.writeDirectoryContents(archiveFrom: filePath(directory), keySet: keys)
            try archive.close()
            try encrypted.close()
            try fileStream.close()
        } catch {
            try? archive.close()
            try? encrypted.close()
            try? fileStream.close()
            throw ArchiveCryptoError.io("cannot write the archive")
        }
    }

    // MARK: Decrypt

    /// Decrypts and extracts `archive` into `destination` (an existing, empty directory). Every entry path is
    /// checked before it is written, nothing is written through a symlink, and the result is scanned afterwards;
    /// on any failure the destination's contents are removed.
    public static func decrypt(archive: URL, passphrase: String, into destination: URL) throws {
        let password = try enginePassword(for: passphrase)
        do {
            try extract(archive: archive, password: password, into: destination)
            try rejectNonRegularEntries(in: destination)
        } catch {
            clearContents(of: destination)
            throw error
        }
    }

    private final class Violation: @unchecked Sendable {
        // The extract filter closure is non-Sendable and called synchronously on the extracting thread(s);
        // the lock makes the one shared flag safe.
        private let lock = NSLock()
        private var value: String?
        func record(_ path: String) {
            lock.lock()
            defer { lock.unlock() }
            if value == nil { value = path }
        }
        var first: String? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private static func extract(archive: URL, password: String, into destination: URL) throws {
        guard
            let input = ArchiveByteStream.fileStream(
                path: filePath(archive), mode: .readOnly, options: [], permissions: FilePermissions(rawValue: 0o600))
        else { throw ArchiveCryptoError.io("cannot open the file") }
        defer { try? input.close() }
        guard let context = ArchiveEncryptionContext(from: input) else { throw ArchiveCryptoError.notEncryptedArchive }
        do { try context.setPassword(password) } catch { throw ArchiveCryptoError.io("cannot set the passphrase") }
        guard let decrypted = ArchiveByteStream.decryptionStream(readingFrom: input, encryptionContext: context)
        else { throw ArchiveCryptoError.wrongPassphrase }
        defer { try? decrypted.close() }
        guard let decoded = ArchiveStream.decodeStream(readingFrom: decrypted) else {
            throw ArchiveCryptoError.corrupted
        }
        defer { try? decoded.close() }

        let violation = Violation()
        let root = destination.resolvingSymlinksInPath().standardizedFileURL
        let filter: ArchiveHeader.EntryFilter = { message, path, _ in
            guard message == .extractBegin else { return .ok }
            let relative = path.string
            if relative.isEmpty { return .ok }  // the archive root
            guard Paths.isSafeRelativePath(relative), !hasSymlinkAncestor(relative, under: root) else {
                violation.record(relative)
                return .cancel
            }
            return .ok
        }
        guard
            let extractor = ArchiveStream.extractStream(
                extractingTo: filePath(root), selectUsing: filter, flags: [.ignoreOperationNotPermitted],
                threadCount: 1)
        else { throw ArchiveCryptoError.io("cannot open the destination") }
        defer { try? extractor.close() }
        do {
            // One thread, so entries are handled in archive order and the symlink check below can't race a write.
            _ = try ArchiveStream.process(readingFrom: decoded, writingTo: extractor, threadCount: 1)
        } catch {
            if let path = violation.first { throw ArchiveCryptoError.unsafeEntry(path) }
            throw ArchiveCryptoError.corrupted
        }
        if let path = violation.first { throw ArchiveCryptoError.unsafeEntry(path) }
    }

    /// True when any existing ancestor directory of `relative` (under `root`) is a symlink.
    private static func hasSymlinkAncestor(_ relative: String, under root: URL) -> Bool {
        var url = root
        for part in relative.split(separator: "/").dropLast() {
            url = url.appending(path: String(part), directoryHint: .isDirectory)
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        }
        return false
    }

    /// Only regular files and plain directories may come out of an archive.
    private static func rejectNonRegularEntries(in directory: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return
        }
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true || (values.isRegularFile != true && values.isDirectory != true) {
                throw ArchiveCryptoError.unsafeEntry(url.lastPathComponent)
            }
        }
    }

    private static func clearContents(of directory: URL) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] {
            try? fm.removeItem(at: directory.appending(path: name))
        }
    }
}
