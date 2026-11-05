#if DEBUG
    import Foundation
    import ReytKit

    /// Simulator-only: `-seedDemoDay` fills today through `JournalStore`, `-seedLateTag` adds a tag a few
    /// seconds after launch (proves `@Query` refreshes from an actor save). Never compiled into release.
    enum DebugSeed {
        static func runIfRequested(_ store: JournalStore) async {
            let args = CommandLine.arguments
            if args.contains("-seedDemoDay") {
                let today = AppClock.today()
                _ = try? await store.updateEntry(
                    today, .text("a slow morning, coffee on the step.\nlong walk after lunch, the light was lovely."))
                _ = try? await store.updateEntry(today, .smileAnswer("the dog fell asleep on my feet."))
                _ = try? await store.updateEntry(today, .score(.good))
                _ = try? await store.updateEntry(today, .moods(["happy", "tired"]))
                // Nine extra tags, each used on an earlier day, so the recent-suggestions cap is visible.
                let extras = ["reading", "cooking", "friends", "garden", "rain", "run", "music", "family", "quiet"]
                for (offset, name) in extras.enumerated() {
                    guard let tag = try? await store.createTag(name: name) else { continue }
                    let day = AppClock.today().adding(days: -(offset + 1))
                    _ = try? await store.updateEntry(day, .tags([tag.id]))
                }
                if let tag = try? await store.createTag(name: "walk") {
                    _ = try? await store.updateEntry(today, .tags([tag.id]))
                }
            }
            if args.contains("-seedSundayPlan") {
                // Plan for the week after Sunday 2026-11-08, so the Sunday, Monday and follow-up flows can be seen.
                if let sunday = DateKey("2026-11-08") {
                    _ = try? await store.saveIntention(sunday: sunday, text: "book the dentist", category: "need-to-do")
                }
            }
            if args.contains("-seedLateTag") {
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    _ = try? await store.createTag(name: "late tag")
                }
            }
        }

        /// `-dumpProtection`: writes `Documents/diagnostics.json` with the file-protection class of the generation
        /// directory, store files and attachments directory. Paths and protection values only, no journal content.
        static func dumpProtectionIfRequested(generation: URL, generationID: String) {
            guard CommandLine.arguments.contains("-dumpProtection") else { return }
            let names = ["store.sqlite", "store.sqlite-wal", "store.sqlite-shm"]
            var report: [String: String] = ["generationID": generationID]
            report["generationDirectory"] = protection(of: generation)
            for name in names {
                report[name] = protection(of: generation.appending(path: name, directoryHint: .notDirectory))
            }
            let attachments = generation.appending(path: "attachments", directoryHint: .isDirectory)
            report["attachments"] = protection(of: attachments)
            guard
                let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
                let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            else { return }
            try? data.write(
                to: documents.appending(path: "diagnostics.json", directoryHint: .notDirectory), options: .atomic)
        }

        private static func protection(of url: URL) -> String {
            guard FileManager.default.fileExists(atPath: url.path) else { return "missing" }
            let value = try? url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
            return value?.rawValue ?? "unknown"
        }
    }
#endif
