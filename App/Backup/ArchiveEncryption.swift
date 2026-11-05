import Foundation
import ReytKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.aea` files written by be reyt. Declared as an exported type in `project.yml`.
    static let beReytArchive = UTType(exportedAs: "local.mitchel.bereyt.archive", conformingTo: .data)

    /// What the restore picker accepts: our own type, plus the system's idea of an `.aea` file.
    static var restoreSources: [UTType] {
        [.beReytArchive] + (UTType(filenameExtension: "aea").map { [$0] } ?? [])
    }
}

/// An already-written `.aea` file for `fileExporter`. The file itself is handed over (not loaded), so a large
/// photo library is never held in memory.
struct ArchiveFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .beReytArchive) { file in
            SentTransferredFile(file.url, allowAccessingOriginalFile: true)
        }
    }
}

enum ExportError: Error, Equatable {
    case noPassphrase
    case tooLong
    case failed
}

struct ExportResult: Sendable {
    let url: URL
    let manifest: ArchiveManifest
    /// Photos left out because their files were missing, for the "n photos couldn't be included" note.
    var skippedAttachments: Int { (manifest.warnings ?? []).filter { $0 == ArchiveWarning.missingAttachment }.count }
}

/// Writes a portable encrypted export of the journal: payload directory (plaintext, in scratch space, deleted
/// in `defer`) then one `.aea` file. Used by manual export and by restore's pre-restore safety copy.
struct PortableExporter: Sendable {
    let paths: Paths
    let generation: URL
    let appVersion: String

    init(paths: Paths, generation: URL) {
        self.paths = paths
        self.generation = generation
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        appVersion = "\(version) (\(build))"
    }

    func export(
        from store: JournalStore, passphrase: String, to destination: URL, lineageID: UUID = UUID()
    ) async throws -> ExportResult {
        let scratch = try ScratchSpace.make()
        defer { ScratchSpace.remove(scratch) }
        let payload = scratch.appending(path: "payload", directoryHint: .isDirectory)
        let options = ArchiveWriter.Options(kind: .portable, appVersion: appVersion, lineageID: lineageID)
        let manifest = try await ArchiveWriter(paths: paths, generation: generation)
            .write(from: store, to: payload, options: options)
        try await Task.detached(priority: .utility) {
            try ArchiveCrypto.encrypt(directory: payload, to: destination, passphrase: passphrase)
        }.value
        return ExportResult(url: destination, manifest: manifest)
    }
}
