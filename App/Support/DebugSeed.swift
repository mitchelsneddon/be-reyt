#if DEBUG
    import Foundation
    import ReytKit
    import UIKit

    /// Simulator-only: `-seedDemoDay` fills today through `JournalStore`, `-seedLateTag` adds a tag a few
    /// seconds after launch (proves `@Query` refreshes from an actor save). Never compiled into release.
    /// Simulator-only: `-forceSaveFailure` makes the next day-page write throw once (App layer, not ReytKit).
    @MainActor enum DebugSaveFailure {
        struct Failure: Error {}

        static var isRequested: Bool { CommandLine.arguments.contains("-forceSaveFailure") }
        private static var spent = false

        /// True exactly once when the flag is set.
        static func consume() -> Bool {
            guard isRequested, !spent else { return false }
            spent = true
            return true
        }
    }

    enum DebugSeed {
        static func runIfRequested(_ store: JournalStore, attachments: AttachmentStore) async {
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
            if args.contains("-seedHistory") { await seedHistory(store, attachments: attachments) }
            if args.contains("-seedSundayPlan") {
                // Plan for the week after Sunday 2026-11-08, so the Sunday, Monday and follow-up flows can be seen.
                if let sunday = DateKey("2026-11-08") {
                    _ = try? await store.saveIntention(sunday: sunday, text: "book the dentist", category: "need-to-do")
                }
            }
            if args.contains("-seedPhotos") {
                // Three generated solid-colour images (two JPEG, one HEIC), through the same import path as the picker.
                let colours: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo]
                for (index, colour) in colours.enumerated() {
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800))
                    let image = renderer.image { ctx in
                        colour.setFill()
                        ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                        UIColor.white.withAlphaComponent(0.5).setFill()
                        ctx.fill(CGRect(x: 0, y: 100 * CGFloat(index + 1), width: 600, height: 60))
                    }
                    guard let data = index == 2 ? image.heicData() : image.jpegData(compressionQuality: 0.9) else {
                        continue
                    }
                    _ = await attachments.importData(data, for: AppClock.today())
                }
            }
            if args.contains("-seedMoreOfThis") {
                // Written on Sunday 2026-11-08 for the review of 2026-10-25: targets 2026-11-08 to 2026-11-14.
                if let sunday = DateKey("2026-10-25"), let saved = DateKey("2026-11-08") {
                    _ = try? await store.saveMoreOfThis(
                        weekStart: sunday, text: "time outdoors, and a long walk with mum.", savedOn: saved)
                }
            }
            if args.contains("-seedWorkouts") { await seedWorkouts(store) }
            if args.contains("-deleteFirstPhoto"), let first = try? await store.attachmentRefs().first {
                _ = try? await attachments.deletePhoto(first)
            }
            if args.contains("-seedLateTag") {
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    _ = try? await store.createTag(name: "late tag")
                }
            }
        }

        /// `-seedWorkouts`: workout snapshots on today through the store (the simulator's Health store cannot be
        /// written without a share entitlement, which release must not carry). Includes the same run from COROS and
        /// Strava, which must show as one card.
        private static func seedWorkouts(_ store: JournalStore) async {
            let today = AppClock.today()
            let midnight = today.date(in: .current)
            func input(
                _ n: Int, _ source: String, _ type: String, hour: Double, minutes: Double, km: Double?, kcal: Double?,
                on day: DateKey? = nil
            )
                -> WorkoutInput
            {
                let dateKey = day ?? today
                let start = (day?.date(in: .current) ?? midnight).addingTimeInterval(hour * 3600)
                return WorkoutInput(
                    healthKitUUID: UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02d", n))
                        ?? UUID(),
                    sourceName: source, activityType: type, start: start, end: start.addingTimeInterval(minutes * 60),
                    dateKey: dateKey, durationSeconds: minutes * 60, distanceMeters: km.map { $0 * 1000 },
                    energyKcal: kcal)
            }
            _ = try? await store.upsertWorkouts([
                input(1, "COROS", "running", hour: 7, minutes: 76, km: 12.3, kcal: 810),
                input(2, "Strava", "running", hour: 7, minutes: 76, km: 12.3, kcal: nil),
                input(3, "Health", "yoga", hour: 18, minutes: 45, km: nil, kcal: 150),
                input(4, "COROS", "swimming", hour: 12.5, minutes: 30, km: 1.2, kcal: 300),
                // Workouts inside earlier review weeks: 2026-11-01 week, and the otherwise empty 2026-09-20 week.
                input(5, "COROS", "running", hour: 7, minutes: 52, km: 9.4, kcal: 620, on: DateKey("2026-11-03")),
                input(6, "Health", "strength", hour: 18, minutes: 40, km: nil, kcal: 210, on: DateKey("2026-11-05")),
                input(7, "COROS", "cycling", hour: 9, minutes: 95, km: 31.0, kcal: 700, on: DateKey("2026-11-06")),
                input(8, "Health", "walking", hour: 17, minutes: 35, km: 2.8, kcal: 120, on: DateKey("2026-09-22")),
            ])
        }

        /// `-seedHistory`: about twenty days across Oct and Nov 2026 with varied fields, a few tags, a Sunday plan with
        /// a follow-up, two photo days, and one day (2026-10-14) with only a prompt assignment (no dot, no row).
        /// Run with `-pretendToday 2026-11-05`. Safe to repeat: every write is a no-op the second time.
        private static func seedHistory(_ store: JournalStore, attachments: AttachmentStore) async {
            func key(_ s: String) -> DateKey { DateKey(s) ?? AppClock.today() }
            let walk = try? await store.createTag(name: "walk").id
            let reading = try? await store.createTag(name: "reading").id
            let friends = try? await store.createTag(name: "friends").id

            struct Seed {
                var day: String
                var text = ""
                var smile: String?
                var rotating: String?
                var score: DayScore?
                var moods: [String] = []
                var tags: [UUID?] = []
            }
            let seeds: [Seed] = [
                Seed(
                    day: "2026-10-03", text: "slow saturday.\nbread in the oven, rain on the window.", tags: [reading]),
                // A week with nothing written (2026-09-20 to 26); only a workout is seeded there.
                Seed(day: "2026-09-15", text: "a quiet tuesday."),
                Seed(day: "2026-10-05", smile: "the neighbour waved from her garden.", score: .okay),
                Seed(
                    day: "2026-10-07", text: "a long meeting day, but the walk home helped.", moods: ["tired"],
                    tags: [walk]),
                Seed(day: "2026-10-09", rotating: "i finally cleared the desk.", score: .good),
                Seed(day: "2026-10-11", text: "sunday. tidied up and made soup.", moods: ["annoyed"]),
                Seed(
                    day: "2026-10-12", text: "Coffee with Priya at the Café on the corner.", score: .excellent,
                    moods: ["happy", "anxious"], tags: [friends]),
                Seed(day: "2026-10-16", smile: "a stranger held the door and we both laughed."),
                Seed(day: "2026-10-18", text: "sunday reset, long walk by the river.", score: .good, tags: [walk]),
                Seed(
                    day: "2026-10-21", text: "couldn't settle. early night.", score: .difficult,
                    moods: ["anxious", "tired"]),
                Seed(
                    day: "2026-10-24", text: "market, then the cinema.\nthe film was slower than i hoped.",
                    tags: [friends]),
                // A genuinely hard day in the week of 2026-10-25, to check the difficult section is used for it.
                Seed(
                    day: "2026-10-26",
                    text:
                        "had a hard conversation with my manager about the project. i came away shaken and could not eat lunch.",
                    score: .difficult, moods: ["stressed"]),
                Seed(
                    day: "2026-10-27", rotating: "a good chapter and a quiet cup of tea.", score: .okay,
                    moods: ["tired"], tags: [reading]),
                Seed(
                    day: "2026-10-29", text: "windy. kept the doors shut and read all afternoon.", score: .difficult,
                    moods: ["sad"], tags: [reading]),
                Seed(
                    day: "2026-10-31", text: "pumpkins on the step, a few kids came by.", score: .good, moods: ["happy"]
                ),
                Seed(day: "2026-11-01", text: "sunday. planned the week over breakfast.", score: .okay),
                Seed(day: "2026-11-02", smile: "found the old cafe still does the good scones.", tags: [friends]),
                Seed(day: "2026-11-03", text: "busy. barely looked up until four.", score: .okay, moods: ["tired"]),
                Seed(
                    day: "2026-11-04",
                    text: "a slow morning, coffee on the step.\nlong walk after lunch, the light was lovely.",
                    smile: "the dog fell asleep on my feet.", score: .good, moods: ["happy", "tired"], tags: [walk]),
                // 2026-11-02 and 11-05 have no score: gaps in the chart for the week of 2026-11-01.
                Seed(day: "2026-11-06", text: "friday. long lunch with friends.", score: .excellent, moods: ["happy"]),
            ]
            for seed in seeds {
                let day = key(seed.day)
                if !seed.text.isEmpty { _ = try? await store.updateEntry(day, .text(seed.text)) }
                if let s = seed.smile { _ = try? await store.updateEntry(day, .smileAnswer(s)) }
                if let r = seed.rotating { _ = try? await store.updateEntry(day, .rotatingAnswer(r)) }
                if let s = seed.score { _ = try? await store.updateEntry(day, .score(s)) }
                if !seed.moods.isEmpty { _ = try? await store.updateEntry(day, .moods(seed.moods)) }
                let ids = seed.tags.compactMap { $0 }
                if !ids.isEmpty { _ = try? await store.updateEntry(day, .tags(ids)) }
            }
            // A Sunday plan with a follow-up the next Sunday: both are content on their own days.
            _ = try? await store.saveIntention(
                sunday: key("2026-10-25"), text: "call mum and book the dentist", category: "need-to-do")
            _ = try? await store.saveFollowUp(
                sourceSunday: key("2026-10-25"), writtenOn: key("2026-11-01"),
                note: "called mum, dentist is booked for the 12th.", skipped: false)
            // A prompt assigned but never answered: must not get a dot or a row.
            _ = try? await store.assignPromptIfNeeded(key("2026-10-14")) { _, _ in
                PromptChoice(id: "debug-seed", text: "what felt easy today?")
            }
            // Photos on two days, only when they have none yet (importing again would add copies).
            for (name, colour) in [("2026-10-12", UIColor.systemTeal), ("2026-10-31", UIColor.systemOrange)] {
                let day = key(name)
                guard let content = try? await store.dayContent(day), content.attachmentCount == 0 else { continue }
                let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { ctx in
                    colour.setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
                }
                if let data = image.jpegData(compressionQuality: 0.8) {
                    _ = await attachments.importData(data, for: day)
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
            let files = (try? FileManager.default.contentsOfDirectory(atPath: attachments.path)) ?? []
            report["attachmentFileCount"] = String(files.count)
            for name in files.sorted() {
                report["attachment:" + name] = protection(
                    of: attachments.appending(path: name, directoryHint: .notDirectory))
            }
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
