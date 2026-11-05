import Foundation
import ReytKit

/// Temporary plaintext lives here (extracted archives, payloads before encryption, the export waiting for the
/// share sheet). Protected `.completeUnlessOpen`, deleted by its owner in `defer`, and swept on every launch.
enum ScratchSpace {
    static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "be-reyt-scratch", directoryHint: .isDirectory)
    }

    static func make() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ArchiveCrypto.makeScratchDirectory(in: root)
    }

    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func clearAll() { try? FileManager.default.removeItem(at: root) }
}
