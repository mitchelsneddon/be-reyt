#if DEBUG
    import Foundation
    import Observation

    /// Throwaway S2 spike. Synthetic data only; never journal content.
    struct SpikeOutcome: Sendable {
        var ok: Bool
        var details: [String: String]
    }

    struct SpikeEntry: Codable, Sendable, Identifiable {
        let check: String
        let timestamp: String
        let ok: Bool
        let details: [String: String]
        var id: String { check + timestamp }
    }

    @MainActor
    @Observable
    final class SpikeResults {
        private(set) var entries: [SpikeEntry] = []
        var running: String?
        var archiveRunning = false
        var backgroundedDuringArchive = false
        var showFolderPicker = false
        var showJSON = false

        static var fileURL: URL { URL.documentsDirectory.appending(path: "spike-results.json") }

        init() {
            if let data = try? Data(contentsOf: Self.fileURL),
                let decoded = try? JSONDecoder().decode([SpikeEntry].self, from: data)
            {
                entries = decoded
            }
        }

        func record(_ check: String, _ outcome: SpikeOutcome) {
            let stamp = Date.now.formatted(.iso8601)
            entries.append(SpikeEntry(check: check, timestamp: stamp, ok: outcome.ok, details: outcome.details))
            persist()
        }

        func last(_ check: String) -> SpikeEntry? {
            entries.last { $0.check == check }
        }

        func run(_ check: String, _ body: @escaping @Sendable () async -> SpikeOutcome) {
            guard running == nil else { return }
            running = check
            Task {
                let outcome = await body()
                record(check, outcome)
                running = nil
            }
        }

        var json: String {
            String(data: encoded() ?? Data(), encoding: .utf8) ?? "[]"
        }

        private func encoded() -> Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(entries)
        }

        private func persist() {
            guard let data = encoded() else { return }
            try? data.write(to: Self.fileURL, options: [.atomic])
        }
    }

    func spikeSeconds(_ d: Duration) -> String {
        let c = d.components
        return String(format: "%.2f", Double(c.seconds) + Double(c.attoseconds) / 1e18)
    }
#endif
