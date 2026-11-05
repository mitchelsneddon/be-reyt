import Foundation
import ReytKit

/// Writes the Markdown journal and its photos into a folder in scratch space, then zips it with the system's
/// `NSFileCoordinator` `.forUploading` (no third-party zip code). The result is readable, not encrypted.
enum MarkdownExporter {
    static func export(journal: ReadableJournal, paths: Paths, generation: URL, today: DateKey) async throws
        -> ReadableExportResult
    {
        try await Task.detached(priority: .userInitiated) {
            let scratch = try ScratchSpace.make()
            do {
                let url = try write(journal: journal, paths: paths, generation: generation, today: today, in: scratch)
                return ReadableExportResult(url: url, scratch: scratch)
            } catch {
                ScratchSpace.remove(scratch)
                throw error
            }
        }.value
    }

    private static func write(journal: ReadableJournal, paths: Paths, generation: URL, today: DateKey, in scratch: URL)
        throws -> URL
    {
        let fm = FileManager.default
        let name = "be reyt journal \(ReadableExportSource.stamp(today))"
        let folder = scratch.appending(path: name, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        ReadableExportSource.protect(folder)

        for file in MarkdownRenderer.render(journal) {
            try Data(file.contents.utf8).write(
                to: folder.appending(path: file.path, directoryHint: .notDirectory),
                options: [.atomic, .completeFileProtectionUnlessOpen])
        }

        let photos = journal.days.flatMap(\.photos)
        if !photos.isEmpty {
            let photoFolder = folder.appending(path: "photos", directoryHint: .isDirectory)
            try fm.createDirectory(at: photoFolder, withIntermediateDirectories: true)
            ReadableExportSource.protect(photoFolder)
            for photo in photos {
                let source = try paths.resolveAttachment(relativePath: photo.relativePath, in: generation)
                let target = photoFolder.appending(path: photo.fileName, directoryHint: .notDirectory)
                try fm.copyItem(at: source, to: target)
                ReadableExportSource.protect(target)
            }
        }

        // The coordinator deletes its zip when the block returns, so copy it out inside the block.
        let destination = scratch.appending(path: "\(name).zip", directoryHint: .notDirectory)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) {
            zipped in
            do { try fm.copyItem(at: zipped, to: destination) } catch { copyError = error }
        }
        if let error = copyError ?? coordinationError { throw error }
        ReadableExportSource.protect(destination)
        try? fm.removeItem(at: folder)
        return destination
    }
}
