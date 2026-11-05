#if DEBUG
    import Foundation
    import SwiftData

    @Model
    final class SpikeNote {
        var text: String
        init(text: String) { self.text = text }
    }

    @MainActor
    enum SpikeStoreCheck {
        private static var container: ModelContainer?

        static var dir: URL {
            URL.applicationSupportDirectory.appending(path: "SpikeData", directoryHint: .isDirectory)
        }
        static var store: URL { dir.appending(path: "store.sqlite") }

        static func protections() -> [String: String] {
            let targets: [(String, URL)] = [
                ("dir", dir),
                ("store", store),
                ("wal", URL(fileURLWithPath: store.path + "-wal")),
                ("shm", URL(fileURLWithPath: store.path + "-shm")),
            ]
            var d: [String: String] = [:]
            for (label, url) in targets {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    d[label] = "missing"
                    continue
                }
                let p = try? url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
                d[label] = p?.rawValue ?? "nil"
            }
            return d
        }

        static func prefixed(_ prefix: String, _ d: [String: String]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: d.map { ("\(prefix).\($0.key)", $0.value) })
        }

        static func insert() throws {
            let c: ModelContainer
            if let container {
                c = container
            } else {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                c = try ModelContainer(for: SpikeNote.self, configurations: ModelConfiguration(url: store))
                container = c
            }
            c.mainContext.insert(SpikeNote(text: "synthetic \(UUID().uuidString)"))
            try c.mainContext.save()
        }

        static func run() -> SpikeOutcome {
            var d: [String: String] = [:]
            do {
                try insert()
                d.merge(prefixed("before", protections())) { $1 }
                let fm = FileManager.default
                let complete: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
                try fm.setAttributes(complete, ofItemAtPath: dir.path)
                for name in ["store.sqlite", "store.sqlite-wal", "store.sqlite-shm"] {
                    let path = dir.appending(path: name).path
                    if fm.fileExists(atPath: path) {
                        do { try fm.setAttributes(complete, ofItemAtPath: path) } catch {
                            d["setError.\(name)"] = String(describing: error)
                        }
                    }
                }
                try insert()
                d.merge(prefixed("after", protections())) { $1 }
                return SpikeOutcome(ok: true, details: d)
            } catch {
                d["error"] = String(describing: error)
                return SpikeOutcome(ok: false, details: d)
            }
        }

        static func recheck() -> SpikeOutcome {
            SpikeOutcome(ok: true, details: prefixed("recheck", protections()))
        }
    }
#endif
