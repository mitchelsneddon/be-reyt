import Foundation

/// Reads the two JSON files of a payload directory. Size caps are enforced by `ArchiveValidator` before this runs;
/// the reader still refuses a file over `maxBytes` so it is safe on its own.
public enum ArchiveReader {
    /// Probe of the fields that must be understood before anything else, so a newer archive whose other fields
    /// changed shape is still reported as newer rather than malformed.
    private struct Header: Decodable {
        var format: String?
        var schemaVersion: Int?
    }

    public static func readManifest(in directory: URL, maxBytes: Int) throws -> ArchiveManifest {
        let bytes = try read(ArchiveNames.manifest, in: directory, maxBytes: maxBytes)
        let decoder = ArchiveCoding.decoder()
        guard let header = try? decoder.decode(Header.self, from: bytes), header.format == ArchiveManifest.formatName
        else { throw ArchiveError.notAnArchive }
        guard let version = header.schemaVersion else { throw ArchiveError.malformed("schemaVersion") }
        if version > ArchiveManifest.supportedSchemaVersion { throw ArchiveError.newerVersion(found: version) }
        do { return try decoder.decode(ArchiveManifest.self, from: bytes) } catch {
            throw ArchiveError.malformed("manifest")
        }
    }

    public static func readData(in directory: URL, maxBytes: Int) throws -> ArchiveData {
        let bytes = try read(ArchiveNames.data, in: directory, maxBytes: maxBytes)
        do { return try ArchiveCoding.decoder().decode(ArchiveData.self, from: bytes) } catch {
            throw ArchiveError.malformed("data")
        }
    }

    private static func read(_ name: String, in directory: URL, maxBytes: Int) throws -> Data {
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ArchiveError.missingFile(name) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxBytes else { throw ArchiveError.fileTooLarge(name) }
        return try Data(contentsOf: url)
    }
}
