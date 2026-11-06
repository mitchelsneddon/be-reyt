import Foundation
import OSLog
import Observation
import ReytKit

/// Drives one Apple Journal import: read the folder off the main thread, show a preview, commit the text in one
/// transaction, then copy photos in one at a time. Journal text is never logged (P2).
@MainActor @Observable
final class AppleJournalImporter {
    enum Phase: Equatable {
        case idle
        case reading(done: Int, total: Int)
        case preview
        case importing
        case finished
        case failed(String)
    }

    struct Result: Equatable {
        var entries: Int
        var days: Int
        var photosImported: Int
        var photosFailed: Int
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: AppleJournalImportPlan?
    private(set) var result: Result?
    var resolutions: [DateKey: AppleJournalConflictResolution] = [:]

    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private var scopedFolder: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "import")

    init(host: ContainerHost, events: JournalEvents) {
        self.host = host
        self.events = events
    }

    var isPresented: Bool { phase != .idle }

    func resolution(for day: DateKey) -> AppleJournalConflictResolution { resolutions[day] ?? .append }

    /// Starts reading `folder`, a security-scoped URL from the file importer.
    func begin(folder: URL) {
        guard phase == .idle || phase == .finished || isFailed, let store = host.store else { return }
        reset()
        if folder.startAccessingSecurityScopedResource() { scopedFolder = folder }
        phase = .reading(done: 0, total: 0)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let hashes = try await store.importedSourceHashes()
                let texted = try await store.daysWithText()
                let plan = try await Self.parse(folder: folder, hashes: hashes, texted: texted) { done, total in
                    Task { @MainActor in self.progress(done: done, total: total) }
                }
                self.readFinished(plan)
            } catch let error as AppleJournalParseError {
                self.fail(Copy.Import.error(error))
            } catch {
                self.logger.error("read failed: \(String(describing: type(of: error)), privacy: .public)")
                self.fail(Copy.Import.noAccess)
            }
        }
    }

    func confirm() {
        guard phase == .preview, let plan, let store = host.store, let attachments = host.attachments else { return }
        phase = .importing
        let chosen = resolutions
        // Strong capture: once importing has started it runs to the end, and every effect must reach the events sink.
        task = Task {
            do {
                let effect = try await store.commitAppleJournalImport(
                    plan: plan, resolutions: chosen, importedAt: Date.now)
                self.events.receive(effect)
                let applied = plan.days.filter { !(plan.conflicts.contains($0.dateKey) && chosen[$0.dateKey] == .skip) }
                var imported = 0
                var failed = 0
                for day in applied {
                    for entry in day.entries {
                        for photo in entry.photos {
                            guard let data = await Self.readPhoto(root: plan.root, relativePath: photo) else {
                                failed += 1
                                continue
                            }
                            switch await attachments.importData(data, for: day.dateKey) {
                            case .success(let photoEffect):
                                self.events.receive(photoEffect)
                                imported += 1
                            case .failure: failed += 1
                            }
                        }
                    }
                }
                self.finish(
                    Result(
                        entries: applied.reduce(0) { $0 + $1.entries.count }, days: applied.count,
                        photosImported: imported, photosFailed: failed))
            } catch {
                self.logger.error("commit failed: \(String(describing: type(of: error)), privacy: .public)")
                self.fail(Copy.Import.genericError)
            }
        }
    }

    /// Closes the sheet. Cancelling during the read stops it; once importing has started it runs to the end.
    func dismiss() {
        guard phase != .importing else { return }
        task?.cancel()
        reset()
    }

    // MARK: Private

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func reset() {
        task = nil
        plan = nil
        result = nil
        resolutions = [:]
        releaseFolder()
        phase = .idle
    }

    private func releaseFolder() {
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = nil
    }

    private func progress(done: Int, total: Int) {
        if case .reading = phase { phase = .reading(done: done, total: total) }
    }

    private func readFinished(_ plan: AppleJournalImportPlan) {
        guard case .reading = phase else { return }
        self.plan = plan
        resolutions = Dictionary(uniqueKeysWithValues: plan.conflicts.map { ($0, .append) })
        phase = .preview
    }

    private func finish(_ result: Result) {
        self.result = result
        releaseFolder()
        phase = .finished
    }

    private func fail(_ message: String) {
        releaseFolder()
        phase = .failed(message)
    }

    private nonisolated static func parse(
        folder: URL, hashes: Set<String>, texted: Set<DateKey>, progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> AppleJournalImportPlan {
        try await Task.detached(priority: .userInitiated) {
            try AppleJournalParser.parse(
                folder: folder, existingHashes: hashes, daysWithText: texted, progress: progress)
        }.value
    }

    /// Reads one photo again at import time and refuses links or anything outside the export folder.
    private nonisolated static func readPhoto(root: URL, relativePath: String) async -> Data? {
        await Task.detached(priority: .utility) {
            guard Paths.isSafeRelativePath(relativePath) else { return nil }
            let url = relativePath.split(separator: "/").reduce(root) {
                $0.appending(path: String($1), directoryHint: .notDirectory)
            }
            let realRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(realRoot + "/")
            else { return nil }
            return try? Data(contentsOf: url)
        }.value
    }
}
