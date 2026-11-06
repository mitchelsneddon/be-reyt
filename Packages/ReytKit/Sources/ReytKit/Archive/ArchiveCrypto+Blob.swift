import AppleArchive
import CryptoKit
import Foundation
import System

extension ArchiveCrypto {
    /// Photo blobs: one file, encrypted with a random 256-bit key (AppleArchive symmetric profile) rather than a
    /// passphrase. The content is the file's bytes, not compressed (photos already are). Streaming.
    public static func encryptBlob(source: URL, to destination: URL, dataKey: Data) throws {
        guard dataKey.count == BlobNaming.keyBytes else { throw ArchiveCryptoError.io("bad key") }
        guard
            let fileStream = ArchiveByteStream.fileStream(
                path: FilePath(destination.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600))
        else { throw ArchiveCryptoError.io("cannot create the file") }
        let context = ArchiveEncryptionContext(
            profile: .hkdf_sha256_aesctr_hmac__symmetric__none, compressionAlgorithm: .none)
        do { try context.setSymmetricKey(SymmetricKey(data: dataKey)) } catch {
            try? fileStream.close()
            throw ArchiveCryptoError.io("cannot set the key")
        }
        guard let encrypted = ArchiveByteStream.encryptionStream(writingTo: fileStream, encryptionContext: context)
        else {
            try? fileStream.close()
            throw ArchiveCryptoError.io("cannot open the stream")
        }
        do {
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            while true {
                let finished: Bool = try autoreleasepool {
                    guard let block = try input.read(upToCount: FileStreaming.chunk), !block.isEmpty else {
                        return true
                    }
                    try block.withUnsafeBytes { buffer in
                        var offset = 0
                        while offset < buffer.count {
                            let written = try encrypted.write(from: UnsafeRawBufferPointer(rebasing: buffer[offset...]))
                            guard written > 0 else { throw ArchiveCryptoError.io("short write") }
                            offset += written
                        }
                    }
                    return false
                }
                if finished { break }
            }
            try encrypted.close()
            try fileStream.close()
        } catch {
            try? encrypted.close()
            try? fileStream.close()
            throw (error as? ArchiveCryptoError) ?? ArchiveCryptoError.io("cannot write the blob")
        }
    }

    /// Decrypts a blob, streaming. The plaintext goes to `destination` when given, and is always hashed: the
    /// caller compares the SHA256 against what the manifest promised. A wrong key or damaged file throws.
    @discardableResult
    public static func decryptBlob(_ blob: URL, dataKey: Data, to destination: URL? = nil) throws -> (
        sha256: String, bytes: Int
    ) {
        guard dataKey.count == BlobNaming.keyBytes else { throw ArchiveCryptoError.io("bad key") }
        guard
            let input = ArchiveByteStream.fileStream(
                path: FilePath(blob.path), mode: .readOnly, options: [], permissions: FilePermissions(rawValue: 0o600))
        else { throw ArchiveCryptoError.io("cannot open the file") }
        defer { try? input.close() }
        guard let context = ArchiveEncryptionContext(from: input) else { throw ArchiveCryptoError.notEncryptedArchive }
        do { try context.setSymmetricKey(SymmetricKey(data: dataKey)) } catch {
            throw ArchiveCryptoError.wrongPassphrase
        }
        guard let decrypted = ArchiveByteStream.decryptionStream(readingFrom: input, encryptionContext: context)
        else { throw ArchiveCryptoError.wrongPassphrase }
        defer { try? decrypted.close() }

        var output: FileHandle?
        if let destination {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw ArchiveCryptoError.io("cannot create the file")
            }
            output = try FileHandle(forWritingTo: destination)
        }
        defer { try? output?.close() }

        var hasher = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: FileStreaming.chunk)
        do {
            while true {
                let count = try buffer.withUnsafeMutableBytes { try decrypted.read(into: $0) }
                if count == 0 { break }
                guard count > 0 else { throw ArchiveCryptoError.corrupted }
                let slice = buffer[0..<count]
                hasher.update(data: slice)
                try output?.write(contentsOf: slice)
                total += count
            }
        } catch {
            if let destination { try? FileManager.default.removeItem(at: destination) }
            throw (error as? ArchiveCryptoError) ?? ArchiveCryptoError.corrupted
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }
}

/// Reading a snapshot back: the data key inside it, and the photo files rebuilt from blobs.
public enum SnapshotBlobs {
    /// The 32-byte key stored as `dataKey.bin` in a snapshot payload.
    public static func readDataKey(in directory: URL) throws -> Data {
        let url = directory.appending(path: ArchiveNames.dataKey, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ArchiveError.missingFile(ArchiveNames.dataKey)
        }
        let key = try Data(contentsOf: url)
        guard key.count == BlobNaming.keyBytes else { throw ArchiveError.malformed(ArchiveNames.dataKey) }
        return key
    }

    /// Fills `attachments/` of a decrypted snapshot payload from its blobs, so it validates and builds like a
    /// portable one. `fetch` returns a local readable file for a blob name (the caller downloads it if needed).
    /// Every file is checked against the manifest's SHA256 and size.
    public static func stage(
        manifest: ArchiveManifest, dataKey: Data, into directory: URL, fetch: (String) throws -> URL
    ) throws {
        let target = directory.appending(path: ArchiveNames.attachmentsDir, directoryHint: .isDirectory)
        for item in manifest.attachments {
            guard let blob = item.blob, BlobNaming.isValidName(blob), ArchiveNames.isSafeExtension(item.ext) else {
                throw ArchiveError.attachmentMismatch(item.id.uuidString)
            }
            let name = ArchiveNames.attachmentFileName(id: item.id, ext: item.ext)
            let destination = target.appending(path: name, directoryHint: .notDirectory)
            let result: (sha256: String, bytes: Int)
            do {
                result = try ArchiveCrypto.decryptBlob(try fetch(blob), dataKey: dataKey, to: destination)
            } catch let error as ArchiveCryptoError {
                throw ArchiveError.verificationFailed("blob \(error)")
            }
            guard result.sha256 == item.sha256, result.bytes == item.bytes else {
                try? FileManager.default.removeItem(at: destination)
                throw ArchiveError.checksumMismatch(name)
            }
        }
    }
}
