#if DEBUG
    import Foundation
    import ReytKit

    /// Simulator-only drivers for the readable exports, so they can run without the file picker:
    /// `-exportMarkdownTo <path.zip>` and `-exportPDFTo <path.pdf>`, with `-exportIncludeWorkouts` to turn the
    /// workouts setting on first. Outcomes (never journal text) go to `Documents/readable-export-debug.txt`.
    enum DebugReadableExport {
        private static func value(after flag: String) -> String? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }

        @MainActor
        static func runIfRequested(host: ContainerHost) async {
            let markdown = value(after: "-exportMarkdownTo")
            let pdf = value(after: "-exportPDFTo")
            guard markdown != nil || pdf != nil else { return }
            var waited = 0
            while host.store == nil || host.generationURL == nil, waited < 400 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            guard let store = host.store, let generation = host.generationURL else { return log("store never opened") }
            // Give the debug seed a moment to finish writing.
            try? await Task.sleep(for: .seconds(4))
            if CommandLine.arguments.contains("-exportIncludeWorkouts") {
                _ = try? await store.updateIncludeWorkoutsInExports(true)
            }
            if CommandLine.arguments.contains("-exportLongEntry"), let day = DateKey("2026-11-07") {
                let line = "a long line of writing to push the entry across several pages, café 😊 שלום. "
                let text = (1...60).map { "paragraph \($0). " + String(repeating: line, count: 4) }.joined(
                    separator: "\n\n")
                _ = try? await store.updateEntry(day, .text(text))
            }
            let include = (try? await store.includeWorkoutsInExports()) ?? false
            let today = AppClock.today()
            do {
                let journal = try await ReadableExportSource.journal(
                    store: store, paths: host.paths, generation: generation, includeWorkouts: include, range: nil)
                if let markdown {
                    let result = try await MarkdownExporter.export(
                        journal: journal, paths: host.paths, generation: generation, today: today)
                    try? FileManager.default.removeItem(atPath: markdown)
                    try FileManager.default.moveItem(at: result.url, to: URL(fileURLWithPath: markdown))
                    ScratchSpace.remove(result.scratch)
                    log("markdown ok days=\(journal.days.count) workouts=\(include)")
                }
                if let pdf {
                    let result = try await PDFExporter.export(
                        journal: journal, paths: host.paths, generation: generation, today: today, progress: { _ in })
                    try? FileManager.default.removeItem(atPath: pdf)
                    try FileManager.default.moveItem(at: result.url, to: URL(fileURLWithPath: pdf))
                    ScratchSpace.remove(result.scratch)
                    log("pdf ok days=\(journal.days.count) workouts=\(include)")
                }
            } catch {
                log("failed \(String(describing: error))")
            }
        }

        private static func log(_ line: String) {
            guard
                let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            else { return }
            let url = documents.appending(path: "readable-export-debug.txt", directoryHint: .notDirectory)
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (existing + line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
#endif
