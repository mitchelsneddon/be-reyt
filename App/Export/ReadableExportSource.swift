import Foundation
import ReytKit
import SwiftUI
import UniformTypeIdentifiers

/// A finished readable export in scratch space. The owner deletes `scratch` when the share sheet is done.
struct ReadableExportResult: Sendable {
    let url: URL
    let scratch: URL
}

enum ReadableExportError: Error, Equatable {
    case nothingToExport
}

/// A zip or PDF handed to `fileExporter` as a file, so a large photo library is never held in memory.
struct ReadableFile: Transferable {
    enum Kind: Sendable { case zip, pdf }

    let url: URL
    let kind: Kind

    var contentType: UTType { kind == .zip ? .zip : .pdf }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { file in
            SentTransferredFile(file.url, allowAccessingOriginalFile: true)
        }
        .exportingCondition { $0.kind == .zip }
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(file.url, allowAccessingOriginalFile: true)
        }
        .exportingCondition { $0.kind == .pdf }
    }
}

enum ReadableExportSource {
    /// One consistent read of the journal, shaped for export. Photos whose files are missing on disk are dropped
    /// first, so no export links to a photo it cannot include.
    static func journal(
        store: JournalStore, paths: Paths, generation: URL, includeWorkouts: Bool, range: ClosedRange<DateKey>?
    ) async throws -> ReadableJournal {
        var data = try await store.archiveSnapshot().data
        data.attachments = data.attachments.filter { a in
            guard let url = try? paths.resolveAttachment(relativePath: a.relativePath, in: generation) else {
                return false
            }
            return FileManager.default.fileExists(atPath: url.path)
        }
        let journal = ReadableJournal(data, includeWorkouts: includeWorkouts, range: range)
        guard !journal.days.isEmpty else { throw ReadableExportError.nothingToExport }
        return journal
    }

    /// "2026-11-08", for file and folder names.
    static func stamp(_ day: DateKey) -> String { day.string }

    static func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
    }
}
