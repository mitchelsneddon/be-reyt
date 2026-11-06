import Foundation
import ReytKit

enum BackupArea: String, Sendable, CaseIterable {
    case snapshots, preRestore, blobs

    var folder: String {
        switch self {
        case .snapshots: BackupFolderNames.snapshots
        case .preRestore: BackupFolderNames.preRestore
        case .blobs: BackupFolderNames.blobs
        }
    }
}

/// A file in the backup set, named as the app wrote it (placeholders already mapped to the real name).
struct DestinationItem: Equatable, Sendable {
    let area: BackupArea
    let name: String
    let bytes: Int?

    var relativePath: String {
        switch area {
        case .blobs: BlobNaming.relativePath(for: BlobNaming.name(fromFileName: name) ?? name) ?? name
        default: "\(area.folder)/\(name)"
        }
    }
}

enum UploadStatus: Equatable, Sendable {
    /// iCloud reports the file as uploaded.
    case uploaded
    /// In iCloud's hands: uploading now, or still waiting for a connection.
    case uploading
    /// The folder is not in iCloud Drive (for example "on my iphone"), so nothing ever uploads.
    case notUbiquitous
    case error
    case missing
}

enum BackupDestinationError: Error, Equatable, Sendable {
    /// The folder was moved, deleted or is out of reach: choose it again.
    case folderMissing
    case notConfigured
    case storageFull
    case io
}

/// Where the backup set lives. One implementation today (a folder the user picked); an app iCloud container
/// destination can be added later without touching the backup logic. Calls block, so callers run them off the
/// main actor.
protocol BackupDestination: Sendable {
    /// Whether the folder is in iCloud Drive. False means a backup here would not survive losing the phone.
    var isUbiquitous: Bool { get }
    /// Every file of the set, recursively for blobs.
    func list() throws -> [DestinationItem]
    /// Copies `temp` into the set at `relativePath`: coordinated, written beside the final name and renamed, so a
    /// reader never sees a half-written file. Replaces an existing file.
    func coordinatedWrite(from temp: URL, to relativePath: String) throws
    /// Runs `body` with a local, readable URL of the file, downloading it first if iCloud had evicted it.
    func coordinatedRead<T>(_ relativePath: String, _ body: (URL) throws -> T) throws -> T
    func remove(_ relativePath: String) throws
    func uploadStatus(_ relativePath: String) -> UploadStatus
    /// False when iCloud holds the file only as a placeholder, so reading it downloads it first.
    func isDownloaded(_ relativePath: String) -> Bool
}
