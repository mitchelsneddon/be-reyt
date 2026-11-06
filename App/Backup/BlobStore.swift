import Foundation
import ReytKit

/// Writes one photo into the backup set as an encrypted blob, and only reports success once it is proven good:
/// encrypted to a temp file, decrypted again and compared with the photo's SHA256, then moved into `blobs/`.
struct BlobStore: Sendable {
    struct Job: Sendable {
        let name: String
        let sha256: String
        let source: URL
    }

    /// The photo's bytes no longer match the checksum its record holds. The run leaves that photo out (with a
    /// warning) rather than failing every backup.
    struct ChecksumMismatch: Error { let blob: String }

    let destination: any BackupDestination

    /// Returns the size of the encrypted blob as written.
    func upload(_ job: Job, dataKey: Data, scratch: URL) throws -> Int {
        guard let relative = BlobNaming.relativePath(for: job.name) else { throw BackupRunError.coded(.other) }
        let temp = scratch.appending(path: "blob-\(job.name).aea", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try ArchiveCrypto.encryptBlob(source: job.source, to: temp, dataKey: dataKey)
            let check = try ArchiveCrypto.decryptBlob(temp, dataKey: dataKey)
            guard check.sha256 == job.sha256 else { throw ChecksumMismatch(blob: job.name) }
        } catch let error as BackupRunError {
            throw error
        } catch let error as ChecksumMismatch {
            throw error
        } catch {
            // The photo could not be read, or the encrypted copy did not decrypt back to it.
            throw BackupRunError.coded(.photoUnreadable)
        }
        let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try destination.coordinatedWrite(from: temp, to: relative)
        return size
    }
}
