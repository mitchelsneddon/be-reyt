import Foundation

/// One consistent read of the journal: every record as DTOs plus the store's write counter at that moment.
public struct ArchiveSnapshot: Sendable {
    public let data: ArchiveData
    public let counter: UInt64
}

extension JournalStore {
    /// Reads every record in a single actor turn, so no write can interleave. A narrative whose fingerprint does
    /// not match the current model input is left out (its review keeps every other field). Nothing is written.
    public func archiveSnapshot() throws -> ArchiveSnapshot {
        var data = try ArchiveData.fetch(from: modelContext)
        for i in data.reviews.indices where data.reviews[i].narrativeJSON != nil {
            let review = data.reviews[i]
            let valid: Bool
            if let week = DateKey(review.weekStartKey) {
                valid = try fingerprintMatches(weekStart: week, stored: review.inputFingerprint)
            } else {
                valid = false
            }
            if !valid { data.reviews[i] = review.omittingNarrative() }
        }
        return ArchiveSnapshot(data: data, counter: writeCounter)
    }
}

/// Writes a payload directory (`manifest.json`, `data.json`, and for `.portable` the attachment files).
/// Encryption and packaging are the caller's job. No device-local state exists in SchemaV1, so none is written.
public struct ArchiveWriter: Sendable {
    public struct Options: Sendable {
        public var kind: ArchiveManifest.Kind
        public var appVersion: String
        public var lineageID: UUID
        public var createdAt: Date
        public var timeZone: TimeZone
        public init(
            kind: ArchiveManifest.Kind, appVersion: String, lineageID: UUID, createdAt: Date = Date.now,
            timeZone: TimeZone = .current
        ) {
            self.kind = kind
            self.appVersion = appVersion
            self.lineageID = lineageID
            self.createdAt = createdAt
            self.timeZone = timeZone
        }
    }

    public static let maxAttempts = 3

    public let paths: Paths
    public let generation: URL

    /// Test hook: runs after the snapshot read and before attachments are copied.
    var afterSnapshotRead: (@Sendable () async -> Void)?

    public init(paths: Paths, generation: URL) {
        self.paths = paths
        self.generation = generation
    }

    /// Writes into `directory`, which must not exist or must be empty. Retries (up to `maxAttempts`) when the store
    /// changed during the attachment copy, then throws `.storeChanged`. On any failure the directory is removed.
    @discardableResult
    public func write(from store: JournalStore, to directory: URL, options: Options) async throws -> ArchiveManifest {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            let contents = try fm.contentsOfDirectory(atPath: directory.path)
            guard contents.isEmpty else { throw ArchiveError.destinationNotEmpty }
        }
        do {
            for _ in 0..<Self.maxAttempts {
                try? fm.removeItem(at: directory)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let snapshot = try await store.archiveSnapshot()
                await afterSnapshotRead?()
                let items = try writePayload(snapshot.data, to: directory, kind: options.kind)
                guard await store.generationCounter() == snapshot.counter else { continue }
                let manifest = ArchiveManifest(
                    format: ArchiveManifest.formatName, kind: options.kind,
                    schemaVersion: ArchiveManifest.supportedSchemaVersion, appVersion: options.appVersion,
                    createdAt: options.createdAt, timeZone: options.timeZone.identifier,
                    lineageID: options.lineageID, counts: ArchiveManifest.Counts(snapshot.data),
                    dateRange: snapshot.data.dateRange, attachments: items)
                try ArchiveCoding.encoder().encode(manifest).write(
                    to: directory.appending(path: ArchiveNames.manifest, directoryHint: .notDirectory))
                return manifest
            }
            throw ArchiveError.storeChanged
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    private func writePayload(
        _ data: ArchiveData, to directory: URL, kind: ArchiveManifest.Kind
    ) throws -> [ArchiveManifest.Attachment] {
        try ArchiveCoding.encoder().encode(data).write(
            to: directory.appending(path: ArchiveNames.data, directoryHint: .notDirectory))
        var items: [ArchiveManifest.Attachment] = []
        for a in data.attachments {
            let ext = (a.relativePath as NSString).pathExtension
            guard ArchiveNames.isSafeExtension(ext) else { throw ArchiveError.unsafePath(a.relativePath) }
            let source = try paths.resolveAttachment(relativePath: a.relativePath, in: generation)
            switch kind {
            case .portable:
                let name = ArchiveNames.attachmentFileName(id: a.id, ext: ext)
                let target = directory.appending(path: ArchiveNames.attachmentsDir, directoryHint: .isDirectory)
                    .appending(path: name, directoryHint: .notDirectory)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw ArchiveError.missingFile(a.relativePath)
                }
                let copied = try FileStreaming.copy(from: source, to: target)
                items.append(.init(id: a.id, ext: ext, sha256: copied.sha256, bytes: copied.bytes, blob: nil))
            case .snapshot:
                // Blobs are produced by the backup run; the manifest records the checksum the record holds.
                let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                items.append(.init(id: a.id, ext: ext, sha256: a.sha256, bytes: size, blob: nil))
            }
        }
        return items.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
