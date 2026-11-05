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
    /// A calm note after an export: saved, and anything that couldn't be included.
    private(set) var exportNote: String?
    var showExporter = false
    private(set) var file: ArchiveFile?
    private(set) var suggestedName = ""

    @ObservationIgnored let host: ContainerHost
    @ObservationIgnored let passphrases: PassphraseStore
    @ObservationIgnored private var scratch: URL?
    @ObservationIgnored private var pendingNote: String?

    init(host: ContainerHost, passphrases: PassphraseStore = PassphraseStore()) {
        self.host = host
        self.passphrases = passphrases
        hasPassphrase = passphrases.hasPassphrase
    }

    func refresh() { hasPassphrase = passphrases.hasPassphrase }

    func savePassphrase(_ value: String) throws {
        try passphrases.set(value)
        hasPassphrase = true
    }

    func isCurrentPassphrase(_ value: String) -> Bool { passphrases.stored() == value }

    // MARK: Export

    /// Writes the encrypted export to scratch space, then offers it to the file exporter.
    func export() async {
        guard exportState != .working, let passphrase = passphrases.stored(), let store = host.store,
            let generation = host.generationURL
        else { return }
        exportState = .working
        exportNote = nil
        do {
            let folder = try ScratchSpace.make()
            scratch = folder
            let name = ArchiveCrypto.exportFileName()
            let result = try await PortableExporter(paths: host.paths, generation: generation)
                .export(
                    from: store, passphrase: passphrase, to: folder.appending(path: name, directoryHint: .notDirectory))
            file = ArchiveFile(url: result.url)
            suggestedName = String(name.dropLast(".aea".count))
            pendingNote = result.skippedAttachments > 0 ? Copy.Export.skipped(result.skippedAttachments) : nil
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
        case .success:
            exportNote = [Copy.Export.saved, pendingNote].compactMap { $0 }.joined(separator: " ")
        case .failure:
            exportState = .failed(Copy.Export.exporterError)
        }
        pendingNote = nil
    }

    func exporterCancelled() {
        cleanUp()
        pendingNote = nil
    }

    func dismissExportMessage() {
        exportState = .idle
        exportNote = nil
    }

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
