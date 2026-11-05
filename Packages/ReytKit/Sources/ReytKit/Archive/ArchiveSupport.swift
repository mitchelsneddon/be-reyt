import CryptoKit
import Foundation

public enum ArchiveError: Error, Equatable, Sendable {
    /// Not a be reyt archive (missing or wrong `format`).
    case notAnArchive
    /// Written by a newer app version. Upstream shows a calm "made by a newer version" message.
    case newerVersion(found: Int)
    case malformed(String)
    case unsafePath(String)
    case fileTooLarge(String)
    case totalTooLarge
    case missingFile(String)
    case checksumMismatch(String)
    case sizeMismatch(String)
    case countMismatch(String)
    case invalidDateKey(String)
    case duplicateKey(String)
    case attachmentMismatch(String)
    case destinationNotEmpty
    /// The journal kept changing while the snapshot was taken.
    case storeChanged
    case verificationFailed(String)
}

/// Naming rules for payload files. Everything derived from untrusted manifest text goes through here.
enum ArchiveNames {
    static let manifest = "manifest.json"
    static let data = "data.json"
    static let dataKey = "dataKey.bin"
    static let attachmentsDir = "attachments"

    /// Extensions are short lowercase alphanumerics, so `{uuid}.{ext}` can never leave `attachments/`.
    static func isSafeExtension(_ ext: String) -> Bool {
        (1...10).contains(ext.count) && ext.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }

    static func attachmentFileName(id: UUID, ext: String) -> String { "\(id.uuidString.lowercased()).\(ext)" }
}

/// Chunked file copy and hashing, so a large photo library never sits in memory.
enum FileStreaming {
    static let chunk = 1 << 20

    /// Copies `source` to `destination` (created, parent directories included) and returns the SHA256 and size.
    static func copy(from source: URL, to destination: URL) throws -> (sha256: String, bytes: Int) {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ArchiveError.malformed("cannot create \(destination.lastPathComponent)")
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        var hasher = SHA256()
        var total = 0
        while true {
            let finished: Bool = try autoreleasepool {
                guard let block = try input.read(upToCount: chunk), !block.isEmpty else { return true }
                hasher.update(data: block)
                try output.write(contentsOf: block)
                total += block.count
                return false
            }
            if finished { break }
        }
        return (hex(hasher.finalize()), total)
    }

    static func sha256(of url: URL) throws -> (sha256: String, bytes: Int) {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        var total = 0
        while true {
            let finished: Bool = try autoreleasepool {
                guard let block = try input.read(upToCount: chunk), !block.isEmpty else { return true }
                hasher.update(data: block)
                total += block.count
                return false
            }
            if finished { break }
        }
        return (hex(hasher.finalize()), total)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
