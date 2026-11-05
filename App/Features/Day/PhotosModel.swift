import Foundation
import Observation
import PhotosUI
import ReytKit
import SwiftUI

/// One day's photo actions. Owns the `dateKey` it was opened with; every store effect goes to `JournalEvents`.
@MainActor @Observable
final class PhotosModel {
    struct Progress: Equatable {
        let current: Int
        let total: Int
    }

    let dateKey: DateKey
    private(set) var progress: Progress?
    /// A calm, dismissable note about the last import or delete; nil when all is well.
    private(set) var message: String?

    @ObservationIgnored private let attachments: AttachmentStore
    @ObservationIgnored private let events: JournalEvents

    init(dateKey: DateKey, attachments: AttachmentStore, events: JournalEvents) {
        self.dateKey = dateKey
        self.attachments = attachments
        self.events = events
    }

    var isImporting: Bool { progress != nil }

    /// Imports the picked items one at a time. A photo that fails (e.g. still downloading from iCloud) is
    /// reported and the rest carry on.
    func importItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, progress == nil else { return }
        message = nil
        var failures: [PhotoImportError] = []
        for (index, item) in items.enumerated() {
            progress = Progress(current: index + 1, total: items.count)
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failures.append(.failed)
                continue
            }
            if let failure = await importData(data) { failures.append(failure) }
        }
        progress = nil
        report(failures)
    }

    /// The single path every photo takes, picker or debug seed. Returns the failure, if any.
    func importData(_ data: Data) async -> PhotoImportError? {
        switch await attachments.importData(data, for: dateKey) {
        case .success(let effect):
            events.receive(effect)
            return nil
        case .failure(let failure):
            return failure
        }
    }

    func delete(_ photo: PhotoRef) async -> Bool {
        do {
            events.receive(try await attachments.deletePhoto(photo))
            message = nil
            return true
        } catch {
            message = Copy.Photos.removeFailed
            return false
        }
    }

    func dismissMessage() { message = nil }

    func thumbnailData(for photo: PhotoRef) async -> Data? { await attachments.thumbnailData(for: photo) }
    func viewerData(for photo: PhotoRef) async -> Data? { await attachments.viewerData(for: photo) }

    private func report(_ failures: [PhotoImportError]) {
        guard let first = failures.first else { return }
        if failures.count > 1 {
            message = Copy.Photos.importFailedMany(failures.count)
            return
        }
        switch first {
        case .unsupported: message = Copy.Photos.unsupported
        case .storageFull: message = Copy.Photos.storageFull
        case .failed: message = Copy.Photos.importFailed
        }
    }
}
