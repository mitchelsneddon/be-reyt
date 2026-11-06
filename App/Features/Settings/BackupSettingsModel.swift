import Foundation
import Observation
import ReytKit

/// Passphrase status and manual export. Owned above the root view, so it survives a restore rebuilding the app.
@MainActor @Observable
final class BackupSettingsModel {
    enum ExportState: Equatable {
        case idle
        case working
        case failed(String)
    }

    private(set) var hasPassphrase: Bool
    private(set) var exportState: ExportState = .idle
    /// What the exporter saved: the file, its size, and how many photos couldn't be included.
    struct SavedExport: Equatable {
        var name: String
        var bytes: Int?
        var skippedPhotos: Int
    }

    private(set) var savedExport: SavedExport?
    var showExporter = false
    private(set) var file: ArchiveFile?
    private(set) var suggestedName = ""

    @ObservationIgnored let host: ContainerHost
    @ObservationIgnored let passphrases: PassphraseStore
    @ObservationIgnored private var scratch: URL?
    @ObservationIgnored private var pending: (bytes: Int?, skippedPhotos: Int)?

    init(host: ContainerHost, passphrases: PassphraseStore = PassphraseStore()) {
        self.host = host
        self.passphrases = passphrases
        hasPassphrase = passphrases.hasPassphrase
    }

    func refresh() { hasPassphrase = passphrases.hasPassphrase }

    /// Called after the passphrase is set or changed: a change replaces the backup data key, and either way the
    /// automatic backup has something to do.
    @ObservationIgnored var onPassphraseChanged: @MainActor () -> Void = {}

    func savePassphrase(_ value: String) throws {
        try passphrases.set(value)
        hasPassphrase = true
        onPassphraseChanged()
    }

    func isCurrentPassphrase(_ value: String) -> Bool { passphrases.stored() == value }

    // MARK: Export

    /// Writes the encrypted export to scratch space, then offers it to the file exporter.
    func export() async {
        guard exportState != .working, let passphrase = passphrases.stored(), let store = host.store,
            let generation = host.generationURL
        else { return }
        exportState = .working
        savedExport = nil
        do {
            let folder = try ScratchSpace.make()
            scratch = folder
            let name = ArchiveCrypto.exportFileName()
            let result = try await PortableExporter(paths: host.paths, generation: generation)
                .export(
                    from: store, passphrase: passphrase, to: folder.appending(path: name, directoryHint: .notDirectory))
            file = ArchiveFile(url: result.url)
            suggestedName = String(name.dropLast(".aea".count))
            let bytes = try? result.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            pending = (bytes, result.skippedAttachments)
            exportState = .idle
            showExporter = true
        } catch {
            cleanUp()
            exportState = .failed(Self.message(for: error))
        }
    }

    func exporterFinished(_ result: Result<URL, Error>) {
        cleanUp()
        switch result {
        case .success(let url):
            savedExport = SavedExport(
                name: url.lastPathComponent, bytes: pending?.bytes, skippedPhotos: pending?.skippedPhotos ?? 0)
        case .failure:
            exportState = .failed(Copy.Export.exporterError)
        }
        pending = nil
    }

    func exporterCancelled() {
        cleanUp()
        pending = nil
    }

    func dismissExportMessage() {
        exportState = .idle
        savedExport = nil
    }

    #if DEBUG
        /// Simulator-only: `-debugExportState working|saved|savedSkipped|failed` shows that inline status.
        func debugShowExport(_ state: String) {
            switch state {
            case "working": exportState = .working
            case "saved":
                savedExport = SavedExport(name: "be reyt backup 2026-11-05.aea", bytes: 4_400_000, skippedPhotos: 0)
            case "savedSkipped":
                savedExport = SavedExport(name: "be reyt backup 2026-11-05.aea", bytes: 4_400_000, skippedPhotos: 1)
            case "failed": exportState = .failed(Copy.Export.failed)
            default: break
            }
        }
    #endif

    private func cleanUp() {
        ScratchSpace.remove(scratch)
        scratch = nil
        file = nil
    }

    private static func message(for error: Error) -> String {
        if (error as? CocoaError)?.code == .fileWriteOutOfSpace { return Copy.Export.storageFull }
        return Copy.Export.failed
    }
}
