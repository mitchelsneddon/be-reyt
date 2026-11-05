import Foundation

/// Result of a successful validation: what the restore preview shows, plus the decoded data so the generation
/// switcher does not parse it twice.
public struct ValidatedArchive: Sendable {
    public let directory: URL
    public let manifest: ArchiveManifest
    public let data: ArchiveData
    public var counts: ArchiveManifest.Counts { manifest.counts }
    public let dateRange: ArchiveManifest.DateRange?
    public let warnings: [String]
}

/// Validates an extracted payload directory. The directory is untrusted (P3): every path is confined to it, sizes
/// are capped and checksums are verified before anything is built from it.
public enum ArchiveValidator {
    public struct Limits: Sendable {
        public var perFileBytes: Int
        public var totalBytes: Int
        public init(perFileBytes: Int, totalBytes: Int) {
            self.perFileBytes = perFileBytes
            self.totalBytes = totalBytes
        }
        public static let `default` = Limits(perFileBytes: 200 * 1024 * 1024, totalBytes: 50 * 1024 * 1024 * 1024)
    }

    /// - Parameter verifyAttachmentFiles: whether attachment files must be present and match their checksums.
    ///   Defaults to true for `portable` and false for `snapshot` (whose blobs are staged later).
    public static func validate(
        directory: URL, limits: Limits = .default, verifyAttachmentFiles: Bool? = nil
    ) throws -> ValidatedArchive {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        var warnings: [String] = []
        let listing = try walk(root, limits: limits, warnings: &warnings)

        let manifest = try ArchiveReader.readManifest(in: root, maxBytes: limits.perFileBytes)
        let data = try ArchiveReader.readData(in: root, maxBytes: limits.perFileBytes)

        try checkCounts(manifest, data)
        try checkRecords(data, warnings: &warnings)
        try checkManifestAttachments(manifest, data, warnings: &warnings)

        if verifyAttachmentFiles ?? (manifest.kind == .portable) {
            for item in manifest.attachments {
                let rel =
                    "\(ArchiveNames.attachmentsDir)/\(ArchiveNames.attachmentFileName(id: item.id, ext: item.ext))"
                guard let size = listing[rel] else { throw ArchiveError.missingFile(rel) }
                guard size == item.bytes else { throw ArchiveError.sizeMismatch(rel) }
                let url = root.appending(path: rel, directoryHint: .notDirectory)
                guard try FileStreaming.sha256(of: url).sha256 == item.sha256 else {
                    throw ArchiveError.checksumMismatch(rel)
                }
            }
        }

        let computed = data.dateRange
        if computed != manifest.dateRange { warnings.append("date range in manifest differs from the data") }
        return ValidatedArchive(
            directory: root, manifest: manifest, data: data, dateRange: computed, warnings: warnings)
    }

    // MARK: Files

    /// Lists regular files (relative path to size), rejecting symlinks, unsafe names and oversize files.
    private static func walk(_ root: URL, limits: Limits, warnings: inout [String]) throws -> [String: Int] {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [])
        else { throw ArchiveError.missingFile(ArchiveNames.manifest) }
        var files: [String: Int] = [:]
        var total = 0
        let prefix = root.path + "/"
        for case let url as URL in walker {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw ArchiveError.unsafePath(url.lastPathComponent) }
            let rel = String(path.dropFirst(prefix.count))
            guard Paths.isSafeRelativePath(rel) else { throw ArchiveError.unsafePath(rel) }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw ArchiveError.unsafePath(rel) }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw ArchiveError.unsafePath(rel) }
            let size = values.fileSize ?? 0
            guard size <= limits.perFileBytes else { throw ArchiveError.fileTooLarge(rel) }
            total += size
            guard total <= limits.totalBytes else { throw ArchiveError.totalTooLarge }
            files[rel] = size
            let known = [ArchiveNames.manifest, ArchiveNames.data, ArchiveNames.dataKey]
            if !known.contains(rel) && !rel.hasPrefix(ArchiveNames.attachmentsDir + "/") {
                warnings.append("unexpected file ignored: \(rel)")
            }
        }
        return files
    }

    // MARK: Contents

    private static func checkCounts(_ manifest: ArchiveManifest, _ data: ArchiveData) throws {
        guard manifest.counts == ArchiveManifest.Counts(data) else {
            throw ArchiveError.countMismatch("manifest counts differ from data.json")
        }
        guard manifest.attachments.count == manifest.counts.attachments else {
            throw ArchiveError.countMismatch("manifest attachment list differs from its count")
        }
    }

    private static func checkRecords(_ data: ArchiveData, warnings: inout [String]) throws {
        func keys(_ field: String, _ values: [String?]) throws {
            for v in values.compactMap({ $0 }) where DateKey(v) == nil { throw ArchiveError.invalidDateKey(field) }
        }
        try keys("entries.dateKey", data.entries.map(\.dateKey))
        try keys("promptAssignments.dateKey", data.promptAssignments.map(\.dateKey))
        try keys("attachments.entryDateKey", data.attachments.map(\.entryDateKey))
        try keys("workouts.dateKey", data.workouts.map(\.dateKey))
        try keys("importRecords.targetDateKey", data.importRecords.map(\.targetDateKey))
        try keys("intentions.sourceSundayKey", data.intentions.map(\.sourceSundayKey))
        try keys("intentions.targetStartKey", data.intentions.map(\.targetStartKey))
        try keys("intentions.targetEndKey", data.intentions.map(\.targetEndKey))
        try keys("intentions.followUpWrittenOnKey", data.intentions.map(\.followUpWrittenOnKey))
        try keys("reviews.weekStartKey", data.reviews.map(\.weekStartKey))
        try keys("reviews.weekEndKey", data.reviews.map(\.weekEndKey))
        try keys("reviews.moreOfThisTargetStartKey", data.reviews.map(\.moreOfThisTargetStartKey))
        try keys("reviews.moreOfThisTargetEndKey", data.reviews.map(\.moreOfThisTargetEndKey))

        func unique<T: Hashable>(_ field: String, _ values: [T]) throws {
            guard Set(values).count == values.count else { throw ArchiveError.duplicateKey(field) }
        }
        try unique("entries.dateKey", data.entries.map(\.dateKey))
        try unique("entries.id", data.entries.map(\.id))
        try unique("tags.id", data.tags.map(\.id))
        try unique("attachments.id", data.attachments.map(\.id))
        try unique("attachments.relativePath", data.attachments.map(\.relativePath))
        try unique("promptAssignments.dateKey", data.promptAssignments.map(\.dateKey))
        try unique("intentions.sourceSundayKey", data.intentions.map(\.sourceSundayKey))
        try unique("reviews.weekStartKey", data.reviews.map(\.weekStartKey))
        try unique("workouts.healthKitUUID", data.workouts.map(\.healthKitUUID))
        try unique("importRecords.sourceIdentityHash", data.importRecords.map(\.sourceIdentityHash))

        for a in data.attachments where !Paths.isSafeRelativePath(a.relativePath) {
            throw ArchiveError.unsafePath(a.relativePath)
        }
        // An attachment on a day with no entry row is valid (a photo-only day), so it is accepted silently.
        let known = Set(data.tags.map(\.id))
        if data.entries.contains(where: { !Set($0.tagIDs).isSubset(of: known) }) {
            warnings.append("some entries reference tags that are not in the archive")
        }
    }

    private static func checkManifestAttachments(
        _ manifest: ArchiveManifest, _ data: ArchiveData, warnings: inout [String]
    ) throws {
        for item in manifest.attachments where !ArchiveNames.isSafeExtension(item.ext) {
            throw ArchiveError.unsafePath("attachment extension")
        }
        let manifestIDs = manifest.attachments.map(\.id)
        guard Set(manifestIDs).count == manifestIDs.count, Set(manifestIDs) == Set(data.attachments.map(\.id)) else {
            throw ArchiveError.attachmentMismatch("manifest and data.json list different attachments")
        }
        let byID = Dictionary(uniqueKeysWithValues: data.attachments.map { ($0.id, $0) })
        for item in manifest.attachments where byID[item.id]?.sha256 != item.sha256 {
            warnings.append("attachment checksum in data.json differs from the manifest")
            break
        }
    }
}
