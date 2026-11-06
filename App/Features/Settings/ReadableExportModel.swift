import Foundation
import Observation
import ReytKit

/// State behind the readable exports screen: the day range, the include-workouts switch (stored in
/// `AppSettings`), and one running export at a time.
@MainActor @Observable
final class ReadableExportModel {
    enum Kind { case markdown, pdf }

    enum State: Equatable {
        case idle
        case working(Double?)
        case failed(String)
    }

    var customRange = false
    var start: Date
    var end: Date
    private(set) var includeWorkouts = false
    private(set) var state: State = .idle
    private(set) var note: String?
    var showExporter = false
    private(set) var file: ReadableFile?
    private(set) var suggestedName = ""

    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private var scratch: URL?
    @ObservationIgnored private let calendar = Calendar.current

    init(host: ContainerHost) {
        self.host = host
        let today = AppClock.today(calendar: calendar)
        end = today.date(in: calendar)
        start = (DateKey(year: today.year, month: 1, day: 1) ?? today).date(in: calendar)
    }

    var today: Date { AppClock.today(calendar: calendar).date(in: calendar) }

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    func load() async {
        guard let store = host.store else { return }
        includeWorkouts = (try? await store.includeWorkoutsInExports()) ?? false
    }

    func setIncludeWorkouts(_ value: Bool) {
        includeWorkouts = value
        guard let store = host.store else { return }
        Task { _ = try? await store.updateIncludeWorkoutsInExports(value) }
    }

    private var range: ClosedRange<DateKey>? {
        guard customRange else { return nil }
        let a = DateKey(date: start, calendar: calendar)
        let b = DateKey(date: end, calendar: calendar)
        return min(a, b)...max(a, b)
    }

    func export(_ kind: Kind) async {
        guard !isWorking, let store = host.store, let generation = host.generationURL else { return }
        state = .working(kind == .pdf ? 0 : nil)
        note = nil
        let paths = host.paths
        let day = AppClock.today(calendar: calendar)
        do {
            let journal = try await ReadableExportSource.journal(
                store: store, paths: paths, generation: generation, includeWorkouts: includeWorkouts, range: range)
            let result: ReadableExportResult
            switch kind {
            case .markdown:
                result = try await MarkdownExporter.export(
                    journal: journal, paths: paths, generation: generation, today: day)
            case .pdf:
                result = try await PDFExporter.export(
                    journal: journal, paths: paths, generation: generation, today: day
                ) { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        if case .working = self?.state { self?.state = .working(fraction) }
                    }
                }
            }
            scratch = result.scratch
            file = ReadableFile(url: result.url, kind: kind == .pdf ? .pdf : .zip)
            suggestedName = result.url.deletingPathExtension().lastPathComponent
            state = .idle
            showExporter = true
        } catch {
            cleanUp()
            state = .failed(Self.message(for: error))
        }
    }

    func exporterFinished(_ result: Result<URL, Error>) {
        cleanUp()
        switch result {
        case .success: note = Copy.ReadableExport.saved
        case .failure: state = .failed(Copy.ReadableExport.exporterError)
        }
    }

    func exporterCancelled() { cleanUp() }

    private func cleanUp() {
        ScratchSpace.remove(scratch)
        scratch = nil
        file = nil
    }

    private static func message(for error: Error) -> String {
        if let error = error as? ReadableExportError, error == .nothingToExport { return Copy.ReadableExport.nothing }
        if (error as? CocoaError)?.code == .fileWriteOutOfSpace { return Copy.ReadableExport.storageFull }
        return Copy.ReadableExport.failed
    }
}
