import Foundation

/// Pure naming and sweep rules for attachment files. The app does the file I/O; these decide what the names are
/// and which files on disk no record owns.
public enum AttachmentLayout {
    /// Image types be reyt keeps, by uniform type identifier. Anything else is refused at import.
    private static let extensions: [String: String] = [
        "public.heic": "heic", "public.heif": "heif", "public.jpeg": "jpg", "public.png": "png",
        "public.tiff": "tiff", "com.compuserve.gif": "gif", "org.webmproject.webp": "webp",
    ]

    /// File extension for a supported image type, nil for anything else.
    public static func fileExtension(forUTI uti: String) -> String? { extensions[uti] }

    /// `{uuid}.{ext}` directly inside the attachments directory, nil for an unsupported type.
    public static func relativePath(id: UUID, uti: String) -> String? {
        fileExtension(forUTI: uti).map { "\(id.uuidString.lowercased()).\($0)" }
    }

    /// Thumbnail location relative to the Caches directory, nil for an invalid generation id.
    public static func thumbnailPath(generationID: String, id: UUID) -> String? {
        guard Paths.isValidGenerationID(generationID) else { return nil }
        return "thumbnails/\(generationID)/\(id.uuidString.lowercased()).jpg"
    }

    /// Files on disk (relative to the attachments directory) that no record points at.
    /// `inFlight` holds files being imported right now, which have no record yet and must not be swept.
    public static func orphans(
        filesOnDisk: [String], recordPaths: [String], inFlight: Set<String> = []
    ) -> [String] {
        let owned = Set(recordPaths).union(inFlight)
        return filesOnDisk.filter { !owned.contains($0) }
    }
}
