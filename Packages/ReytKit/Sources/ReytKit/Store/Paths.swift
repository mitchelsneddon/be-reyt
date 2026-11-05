import Foundation

public enum PathError: Error, Equatable, Sendable {
    case invalidGenerationID
    case unsafeRelativePath
}

/// On-disk layout, rooted at an injectable base (Application Support in the app, a temp dir in tests).
///
///     base/Data/current            pointer file holding the current generation id
///     base/Data/<gen>/store.sqlite
///     base/Data/<gen>/attachments/
///     base/Device/                 device-local state, never archived
public struct Paths: Sendable {
    public let base: URL

    public init(base: URL) { self.base = base }

    public var dataRoot: URL { base.appending(path: "Data", directoryHint: .isDirectory) }
    public var currentPointer: URL { dataRoot.appending(path: "current", directoryHint: .notDirectory) }
    public var deviceRoot: URL { base.appending(path: "Device", directoryHint: .isDirectory) }

    public func generation(_ id: String) -> URL {
        dataRoot.appending(path: id, directoryHint: .isDirectory)
    }

    public func store(in generation: URL) -> URL {
        generation.appending(path: "store.sqlite", directoryHint: .notDirectory)
    }

    public func attachments(in generation: URL) -> URL {
        generation.appending(path: "attachments", directoryHint: .isDirectory)
    }

    /// Generation ids are path components, so only a conservative alphabet is allowed.
    public static func isValidGenerationID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Reads and validates the pointer file. The file is untrusted input, so a bad value yields nil.
    public func currentGenerationID() -> String? {
        guard let raw = try? String(contentsOf: currentPointer, encoding: .utf8) else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Paths.isValidGenerationID(id) ? id : nil
    }

    /// Lexical check: refuses empty, absolute, `~`, `.`/`..`/empty components, backslashes and NUL.
    public static func isSafeRelativePath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
            !relativePath.contains("\0"), !relativePath.hasPrefix("~")
        else { return false }
        return relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Resolves an attachment's relative path inside `generation`'s attachments directory, or throws.
    /// Refuses empty, absolute, `.`/`..`/empty components, backslashes, NUL, and anything whose real path
    /// (following existing symlinks) leaves the attachments directory.
    public func resolveAttachment(relativePath: String, in generation: URL) throws -> URL {
        guard Paths.isSafeRelativePath(relativePath) else { throw PathError.unsafeRelativePath }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let root = attachments(in: generation)
        let resolved = parts.reduce(root) { $0.appending(path: String($1), directoryHint: .notDirectory) }

        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let realTarget = Paths.realPath(of: resolved)
        guard realTarget.hasPrefix(realRoot + "/") else { throw PathError.unsafeRelativePath }
        return resolved
    }

    /// Real path with symlinks resolved, including when the leaf does not exist yet:
    /// resolves the deepest existing ancestor, then re-appends the missing components.
    private static func realPath(of url: URL) -> String {
        var existing = url
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        let base = existing.resolvingSymlinksInPath().standardizedFileURL
        return missing.reduce(base) { $0.appending(path: $1) }.path
    }

    /// Sets `.complete` protection on `directory`, the store file and its `-wal`/`-shm` siblings.
    /// iOS only; a no-op elsewhere so tests run on macOS. Missing files are skipped.
    public func applyCompleteProtection(toGeneration generation: URL) throws {
        #if os(iOS)
            let store = store(in: generation)
            let targets = [
                generation, store,
                URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm"),
            ]
            for url in targets where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            }
        #endif
    }

    /// Sets `.complete` protection on a single directory (iOS only).
    public static func applyCompleteProtection(toDirectory directory: URL) throws {
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }
}
