import CryptoKit
import Foundation
import ImageIO
import OSLog
import ReytKit
import UniformTypeIdentifiers

enum PhotoImportError: Error, Equatable, Sendable {
    case unsupported
    case storageFull
    case failed
}

/// A photo's record id and file path, as the views hand them to the store.
typealias PhotoRef = AttachmentRef

/// Photo file I/O: originals under the current generation's attachments directory (complete protection),
/// thumbnails under Caches (rebuilt on demand, never backed up). `JournalStore` owns the records; this owns the files.
actor AttachmentStore {
    static let thumbnailPixels = 216  // 3x the 72 pt strip thumbnail
    static let viewerPixels = 2400

    private let store: JournalStore
    private let paths: Paths
    private let generation: URL
    private let generationID: String
    private let cachesBase: URL
    private var inFlight: Set<String> = []
    private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "photos")

    init(
        store: JournalStore, paths: Paths, generation: URL, generationID: String,
        cachesBase: URL = .cachesDirectory
    ) {
        self.store = store
        self.paths = paths
        self.generation = generation
        self.generationID = generationID
        self.cachesBase = cachesBase
    }

    // MARK: Import

    /// Writes the original bytes, then the record. A partial file is removed on any failure.
    func importData(_ data: Data, for day: DateKey) async -> Result<StoreEffect, PhotoImportError> {
        let id = UUID()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let uti = CGImageSourceGetType(source) as String?,
            let relativePath = AttachmentLayout.relativePath(id: id, uti: uti)
        else { return .failure(.unsupported) }
        let pixelSize = Self.pixelSize(of: source)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let destination: URL
        do {
            destination = try paths.resolveAttachment(relativePath: relativePath, in: generation)
            try FileManager.default.createDirectory(
                at: paths.attachments(in: generation), withIntermediateDirectories: true)
        } catch {
            logger.error("path failed: \(String(describing: type(of: error)), privacy: .public)")
            return .failure(.failed)
        }

        inFlight.insert(relativePath)
        defer { inFlight.remove(relativePath) }
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: destination)
            logger.error("write failed: \(String(describing: type(of: error)), privacy: .public)")
            return .failure((error as? CocoaError)?.code == .fileWriteOutOfSpace ? .storageFull : .failed)
        }
        do {
            let effect = try await store.addAttachmentRecord(
                id: id, dateKey: day, relativePath: relativePath, uti: uti, sha256: sha, pixelSize: pixelSize)
            return .success(effect)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            logger.error("record failed: \(String(describing: type(of: error)), privacy: .public)")
            return .failure(.failed)
        }
    }

    // MARK: Delete

    /// Record first, so a half-finished delete never leaves a record pointing at nothing. A file that
    /// can't be removed becomes an orphan, which `sweepOrphans` collects on the next launch.
    func deletePhoto(_ photo: PhotoRef) async throws -> StoreEffect {
        let effect = try await store.deleteAttachmentRecord(id: photo.id)
        if let original = try? paths.resolveAttachment(relativePath: photo.relativePath, in: generation) {
            do {
                try FileManager.default.removeItem(at: original)
            } catch {
                logger.error("file removal failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        if let thumbnail = thumbnailURL(for: photo.id) { try? FileManager.default.removeItem(at: thumbnail) }
        return effect
    }

    /// Waits (bounded) for photo imports that are mid-write, so restore never races one.
    func waitForIdle(timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while !inFlight.isEmpty, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Removes attachment files no record owns. Only touches the current generation's attachments directory.
    func sweepOrphans() async {
        guard let refs = try? await store.attachmentRefs() else { return }
        let files = Self.relativeFiles(under: paths.attachments(in: generation))
        let stale = AttachmentLayout.orphans(
            filesOnDisk: files, recordPaths: refs.map(\.relativePath), inFlight: inFlight)
        for relative in stale {
            guard let url = try? paths.resolveAttachment(relativePath: relative, in: generation) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        if !stale.isEmpty { logger.info("swept \(stale.count) orphaned photo files") }
    }

    /// Regular files under `directory` (symlinks and hidden files skipped), as paths relative to it.
    private nonisolated static func relativeFiles(under directory: URL) -> [String] {
        let root = directory.standardizedFileURL
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { return [] }
        var files: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(root.path + "/") { files.append(String(path.dropFirst(root.path.count + 1))) }
        }
        return files
    }

    // MARK: Reading

    /// JPEG thumbnail bytes, from the Caches copy when present, rebuilt from the original when not.
    func thumbnailData(for photo: PhotoRef) -> Data? {
        guard let cached = thumbnailURL(for: photo.id) else { return nil }
        if let data = try? Data(contentsOf: cached) { return data }
        guard let original = try? paths.resolveAttachment(relativePath: photo.relativePath, in: generation),
            let data = Self.jpegData(from: original, maxPixel: Self.thumbnailPixels)
        else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cached, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("thumbnail cache failed: \(String(describing: type(of: error)), privacy: .public)")
        }
        return data
    }

    /// A screen-sized JPEG for the full-screen viewer (never the full-resolution original).
    func viewerData(for photo: PhotoRef) -> Data? {
        guard let original = try? paths.resolveAttachment(relativePath: photo.relativePath, in: generation)
        else { return nil }
        return Self.jpegData(from: original, maxPixel: Self.viewerPixels)
    }

    private func thumbnailURL(for id: UUID) -> URL? {
        AttachmentLayout.thumbnailPath(generationID: generationID, id: id).map {
            cachesBase.appending(path: $0, directoryHint: .notDirectory)
        }
    }

    // MARK: ImageIO

    private static func pixelSize(of source: CGImageSource) -> PixelSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return PixelSize(width: w, height: h)
    }

    private static func jpegData(from url: URL, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(sink, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(sink) ? out as Data : nil
    }
}
