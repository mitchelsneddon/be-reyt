import CryptoKit
import Foundation
import SwiftData
import Testing

@testable import ReytKit

/// A file-backed journal at `base/Data/g1` with a record of every SchemaV1 type, every optional set (and a second
/// row with them all empty), Unicode text and real attachment files. `base/Data/current` points at g1.
final class ArchiveFixture {
    let base: URL
    let paths: Paths
    let generation: URL
    let container: ModelContainer
    let store: JournalStore

    static let entryDay = DateKey("2026-11-03")!
    static let validWeek = DateKey("2026-11-01")!
    static let staleWeek = DateKey("2026-10-25")!
    static let photoOnlyDay = "2026-11-04"
    let tagA = UUID()
    let tagB = UUID()
    let photoA = UUID()
    let photoB = UUID()
    /// 3 MB, so the chunked copy loops more than once.
    let photoABytes = Data((0..<(3 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    let photoBBytes = Data("tiny".utf8)

    init() async throws {
        base = FileManager.default.temporaryDirectory.appending(path: "reyt-archive-\(UUID().uuidString)")
        paths = Paths(base: base)
        generation = paths.generation("g1")
        try FileManager.default.createDirectory(
            at: paths.attachments(in: generation), withIntermediateDirectories: true)
        try Data("g1".utf8).write(to: paths.currentPointer)
        container = try GenerationSwitcher.openContainer(at: paths.store(in: generation))
        store = JournalStore(
            modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000.5) },
            timeZone: TimeZone(identifier: "Europe/London")!)
        try populate()
        try await addReview(week: Self.validWeek, valid: true)
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    // Binary-exact fractions so the millisecond ISO8601 round trip is lossless.
    func t(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + seconds) }

    private func populate() throws {
        let c = ModelContext(container)
        c.insert(
            DailyEntry(
                dateKey: Self.entryDay.string, originalTimeZoneID: "Asia/Tokyo",
                text: "café ☕️ naïve 😀👨‍👩‍👧 שלום עולם مرحبا بالعالم\nline two",
                smileAnswer: "ça va 🙂", rotatingAnswer: "שלום", dayScore: 4, moodIDs: ["calm", "grateful"],
                tagIDs: [tagA, tagB], createdAt: t(0.25), updatedAt: t(1.5)))
        c.insert(
            DailyEntry(
                dateKey: "2026-11-02", originalTimeZoneID: "UTC", text: "", smileAnswer: "", rotatingAnswer: nil,
                dayScore: nil, moodIDs: [], tagIDs: [], createdAt: t(2), updatedAt: t(2)))
        c.insert(Tag(id: tagA, name: "Zoë", createdAt: t(3)))
        c.insert(Tag(id: tagB, name: "働く", createdAt: t(4)))
        c.insert(
            Attachment(
                id: photoA, entryDateKey: Self.entryDay.string, relativePath: "\(photoA.uuidString.lowercased()).heic",
                uti: "public.heic", sha256: Self.sha(photoABytes), pixelSize: PixelSize(width: 4032, height: 3024),
                createdAt: t(5)))
        c.insert(
            Attachment(
                id: photoB, entryDateKey: Self.photoOnlyDay, relativePath: "\(photoB.uuidString.lowercased()).png",
                uti: "public.png", sha256: Self.sha(photoBBytes), pixelSize: nil, createdAt: t(6)))
        try photoABytes.write(to: attachmentFile("\(photoA.uuidString.lowercased()).heic"))
        try photoBBytes.write(to: attachmentFile("\(photoB.uuidString.lowercased()).png"))
        c.insert(
            PromptAssignment(dateKey: Self.entryDay.string, promptID: "p1", promptText: "what 🌱?", assignedAt: t(7)))
        c.insert(PromptAssignment(dateKey: "2026-11-02", promptID: "p2", promptText: "", assignedAt: t(8)))
        c.insert(
            WeeklyIntention(
                sourceSundayKey: "2026-11-01", targetStartKey: "2026-11-02", targetEndKey: "2026-11-08",
                text: "walk more 🚶", category: "health", followUpNote: "did ok", followUpWrittenOnKey: "2026-11-08",
                followUpSkipped: false))
        c.insert(
            WeeklyIntention(
                sourceSundayKey: "2026-10-25", targetStartKey: "2026-10-26", targetEndKey: "2026-11-01", text: "",
                category: nil, followUpNote: nil, followUpWrittenOnKey: "2026-11-01", followUpSkipped: true))
        c.insert(
            WorkoutSnapshot(
                healthKitUUID: UUID(), sourceName: "Watch ⌚️", activityType: "running", start: t(9), end: t(10),
                dateKey: "2026-11-02", timeZoneID: "Europe/London", durationSeconds: 1800.5, distanceMeters: 5000.25,
                energyKcal: 310.75))
        c.insert(
            WorkoutSnapshot(
                healthKitUUID: UUID(), sourceName: "", activityType: "other", start: t(11), end: t(12),
                dateKey: "2026-11-03", timeZoneID: nil, durationSeconds: 60, distanceMeters: nil, energyKcal: nil))
        c.insert(
            ImportRecord(
                sourceIdentityHash: "hash-1", importedAt: t(13), sourceArchiveHash: "arch", targetDateKey: "2026-11-02",
                sourceTitle: "Título 📖", sourceTimestamp: t(14), sectionIndex: 2))
        c.insert(
            ImportRecord(
                sourceIdentityHash: "hash-2", importedAt: t(15), sourceArchiveHash: "arch", targetDateKey: "2026-11-03",
                sourceTitle: nil, sourceTimestamp: nil, sectionIndex: 0))
        c.insert(AppSettings(reminderEnabled: false, reminderHour: 7, includeWorkoutsInExports: true))
        // A purged review (no narrative) with "more of this" set, for the previous week.
        c.insert(
            WeeklyReview(
                weekStartKey: Self.staleWeek.string, weekEndKey: Self.staleWeek.adding(days: 6).string,
                timeZoneID: "Europe/London", unlockedAt: t(16), sourceRevision: 3, narrativeJSON: nil,
                inputFingerprint: nil, generatedAt: nil, promptVersion: 2, osBuild: "27A1",
                purgeReason: "source changed",
                moreOfThisText: "más 🌿", moreOfThisTargetStartKey: "2026-11-02", moreOfThisTargetEndKey: "2026-11-08"))
        try c.save()
    }

    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func attachmentFile(_ name: String) -> URL {
        paths.attachments(in: generation).appending(path: name, directoryHint: .notDirectory)
    }

    /// Adds a review for `week` with a narrative. `valid` decides whether its fingerprint matches the week's input.
    func addReview(week: DateKey, valid: Bool) async throws {
        let fp =
            valid
            ? try ReviewFingerprint.compute(try await store.reflectionInput(weekStart: week)) : "not-the-fingerprint"
        let c = ModelContext(container)
        c.insert(
            WeeklyReview(
                weekStartKey: week.string, weekEndKey: week.adding(days: 6).string, timeZoneID: "Europe/London",
                unlockedAt: t(17), sourceRevision: 1, narrativeJSON: "{\"summary\":\"naïve 😀\"}",
                inputFingerprint: fp, generatedAt: t(18.5), promptVersion: 1, osBuild: "27A2", purgeReason: nil,
                moreOfThisText: "keep", moreOfThisTargetStartKey: "2026-11-09", moreOfThisTargetEndKey: "2026-11-15"))
        try c.save()
    }

    func rawData() throws -> ArchiveData { try ArchiveData.fetch(from: ModelContext(container)) }

    /// Writes a portable payload into a fresh temp directory and returns it.
    func writePayload(kind: ArchiveManifest.Kind = .portable) async throws -> URL {
        let dir = base.appending(path: "payload-\(UUID().uuidString)")
        let options = ArchiveWriter.Options(
            kind: kind, appVersion: "1.0 (1)", lineageID: UUID(), createdAt: t(20),
            timeZone: TimeZone(identifier: "Europe/London")!)
        try await ArchiveWriter(paths: paths, generation: generation).write(from: store, to: dir, options: options)
        return dir
    }
}

func readJSON(_ url: URL) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object).write(to: url)
}
