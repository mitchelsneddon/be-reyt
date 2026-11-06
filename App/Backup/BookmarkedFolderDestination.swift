import Foundation
import ReytKit

/// A folder the user picked (for example in iCloud Drive), remembered as a bookmark. The backup set lives in
/// `be reyt backups/{snapshots,blobs,pre-restore}` inside it. Every call opens security-scoped access for its own
/// duration, so no access is held between runs.
struct BookmarkedFolderDestination: BackupDestination {
    private let root: URL
    private let scopeURL: URL
    let isUbiquitous: Bool
    /// Set when the stored bookmark was stale and has been re-created; the caller saves it.
    let refreshedBookmark: Data?

    /// Resolves a stored bookmark. A stale one is re-created. A folder that is gone throws `folderMissing`.
    init(bookmark: Data) throws {
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            throw BackupDestinationError.folderMissing
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard Self.isDirectory(url) else { throw BackupDestinationError.folderMissing }
        refreshedBookmark =
            stale ? try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        scopeURL = url
        root = Self.setRoot(in: url)
        isUbiquitous = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
    }

    /// DEBUG: a plain local folder, treated as not in iCloud.
    init(plainFolder url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        scopeURL = url
        root = Self.setRoot(in: url)
        isUbiquitous = false
        refreshedBookmark = nil
    }

    /// What the picker returned: creates the set's folders, and returns the destination and the bookmark to keep.
    static func chosen(_ picked: URL) throws -> (destination: BookmarkedFolderDestination, bookmark: Data) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        guard isDirectory(picked) else { throw BackupDestinationError.folderMissing }
        let bookmark: Data
        do {
            bookmark = try picked.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw BackupDestinationError.folderMissing
        }
        let destination = try BookmarkedFolderDestination(bookmark: bookmark)
        try destination.withAccess { try destination.createFolders() }
        return (destination, bookmark)
    }

    private static func setRoot(in url: URL) -> URL {
        url.lastPathComponent == BackupFolderNames.root
            ? url : url.appending(path: BackupFolderNames.root, directoryHint: .isDirectory)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// The picked folder's name, for the status line.
    var folderName: String { scopeURL.lastPathComponent }

    // MARK: Access

    private func withAccess<T>(_ body: () throws -> T) throws -> T {
        let scoped = scopeURL.startAccessingSecurityScopedResource()
        defer { if scoped { scopeURL.stopAccessingSecurityScopedResource() } }
        guard Self.isDirectory(scopeURL) else { throw BackupDestinationError.folderMissing }
        return try body()
    }

    private func createFolders() throws {
        for area in BackupArea.allCoordinated {
            try coordinatedCreateDirectory(root.appending(path: area.folder, directoryHint: .isDirectory))
        }
    }

    private func coordinatedCreateDirectory(_ url: URL) throws {
        try coordinateWrite(url, options: []) { target in
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }
    }

    private func url(_ relativePath: String) throws -> URL {
        guard Paths.isSafeRelativePath(relativePath) else { throw BackupDestinationError.io }
        return relativePath.split(separator: "/").reduce(root) { $0.appending(path: String($1)) }
    }

    // MARK: List

    func list() throws -> [DestinationItem] {
        try withAccess {
            var items: [DestinationItem] = []
            for area in [BackupArea.snapshots, .preRestore] {
                for entry in try entries(root.appending(path: area.folder, directoryHint: .isDirectory)) {
                    if let name = BackupFolderNames.normalized(entry.name) {
                        items.append(DestinationItem(area: area, name: name, bytes: entry.bytes))
                    }
                }
            }
            let blobs = root.appending(path: BackupFolderNames.blobs, directoryHint: .isDirectory)
            for shard in try entries(blobs) where shard.isDirectory {
                for entry in try entries(blobs.appending(path: shard.name, directoryHint: .isDirectory)) {
                    if let name = BackupFolderNames.normalized(entry.name), BlobNaming.name(fromFileName: name) != nil {
                        items.append(DestinationItem(area: .blobs, name: name, bytes: entry.bytes))
                    }
                }
            }
            return items
        }
    }

    private struct Entry {
        let name: String
        let bytes: Int?
        let isDirectory: Bool
    }

    /// Directory entries without downloading anything: evicted files are listed with their sizes.
    private func entries(_ directory: URL) throws -> [Entry] {
        var result: [Entry] = []
        var failure: Error?
        try coordinateRead(directory, options: [.immediatelyAvailableMetadataOnly]) { readable in
            do {
                let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
                let urls = try FileManager.default.contentsOfDirectory(
                    at: readable, includingPropertiesForKeys: keys, options: [])
                result = urls.map { url in
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    return Entry(
                        name: url.lastPathComponent, bytes: values?.fileSize, isDirectory: values?.isDirectory == true)
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                result = []  // a folder not made yet is an empty one
            } catch {
                failure = error
            }
        }
        if failure != nil { throw BackupDestinationError.io }
        return result
    }

    // MARK: Write, read, remove

    func coordinatedWrite(from temp: URL, to relativePath: String) throws {
        let final = try url(relativePath)
        try withAccess {
            try coordinatedCreateDirectory(final.deletingLastPathComponent())
            try coordinateWrite(final, options: [.forReplacing]) { target in
                let fm = FileManager.default
                let partial = target.deletingLastPathComponent().appending(
                    path: BackupFolderNames.partialName(for: target.lastPathComponent), directoryHint: .notDirectory)
                do {
                    try fm.copyItem(at: temp, to: partial)
                    if fm.fileExists(atPath: target.path) {
                        _ = try fm.replaceItemAt(target, withItemAt: partial)
                    } else {
                        try fm.moveItem(at: partial, to: target)
                    }
                } catch {
                    try? fm.removeItem(at: partial)
                    throw Self.mapWriteError(error)
                }
            }
        }
    }

    func coordinatedRead<T>(_ relativePath: String, _ body: (URL) throws -> T) throws -> T {
        let file = try url(relativePath)
        return try withAccess {
            // A coordinated read makes iCloud Drive download the file first if it was evicted.
            var coordinationError: NSError?
            var result: Result<T, Error> = .failure(BackupDestinationError.io)
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { readable in
                result = Result { try body(readable) }
            }
            if coordinationError != nil { throw BackupDestinationError.io }
            return try result.get()
        }
    }

    func remove(_ relativePath: String) throws {
        let file = try url(relativePath)
        try withAccess {
            try coordinateWrite(file, options: [.forDeleting]) { target in
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    // MARK: Upload status

    func uploadStatus(_ relativePath: String) -> UploadStatus {
        guard isUbiquitous else { return .notUbiquitous }
        guard let file = try? url(relativePath) else { return .missing }
        let scoped = scopeURL.startAccessingSecurityScopedResource()
        defer { if scoped { scopeURL.stopAccessingSecurityScopedResource() } }
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
            .ubiquitousItemUploadingErrorKey,
        ]
        guard FileManager.default.fileExists(atPath: file.path) || Self.placeholderExists(for: file),
            let values = try? file.resourceValues(forKeys: keys)
        else { return .missing }
        guard values.isUbiquitousItem == true else { return .notUbiquitous }
        if values.ubiquitousItemUploadingError != nil { return .error }
        if values.ubiquitousItemIsUploaded == true { return .uploaded }
        return .uploading
    }

    private static func placeholderExists(for file: URL) -> Bool {
        let placeholder = file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    // MARK: Coordination helpers

    private func coordinateWrite(_ url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void)
        throws
    {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { writable in
            do { try body(writable) } catch { failure = error }
        }
        if let failure { throw failure }
        if let coordinationError { throw Self.mapWriteError(coordinationError) }
    }

    private func coordinateRead(_ url: URL, options: NSFileCoordinator.ReadingOptions, _ body: (URL) -> Void) throws {
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: url, options: options, error: &coordinationError, byAccessor: body)
        if coordinationError != nil { throw BackupDestinationError.io }
    }

    private static func mapWriteError(_ error: Error) -> Error {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace {
            return BackupDestinationError.storageFull
        }
        if (error as NSError).domain == NSPOSIXErrorDomain, (error as NSError).code == Int(ENOSPC) {
            return BackupDestinationError.storageFull
        }
        return error
    }
}

extension BackupArea {
    static let allCoordinated: [BackupArea] = [.snapshots, .blobs, .preRestore]
}
