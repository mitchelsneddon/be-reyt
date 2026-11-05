import Foundation
import SwiftData
import Testing

@testable import ReytKit

@Suite("SchemaV1")
struct SchemaV1Tests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test("schema version and plan")
    func version() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV1.models.count == 9)
        #expect(BeReytMigrationPlan.schemas.count == 1)
        #expect(BeReytMigrationPlan.stages.isEmpty)
    }

    @Test("one of every record round trips")
    func roundTrip() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let tagID = UUID()
        let wid = UUID()

        ctx.insert(
            DailyEntry(
                dateKey: "2026-11-05", originalTimeZoneID: "America/Edmonton", text: "hi", smileAnswer: "tea",
                rotatingAnswer: "x", dayScore: 4, moodIDs: ["happy", "tired"], tagIDs: [tagID], createdAt: now,
                updatedAt: now))
        ctx.insert(AppSettings())
        ctx.insert(PromptAssignment(dateKey: "2026-11-05", promptID: "p1", promptText: "what?", assignedAt: now))
        ctx.insert(SchemaV1.Tag(id: tagID, name: "run", createdAt: now))
        ctx.insert(
            SchemaV1.Attachment(
                entryDateKey: "2026-11-05", relativePath: "a.heic", uti: "public.heic", sha256: "ab",
                pixelSize: PixelSize(width: 3, height: 4), createdAt: now))
        ctx.insert(
            WorkoutSnapshot(
                healthKitUUID: wid, sourceName: "COROS", activityType: "running", start: now, end: now,
                dateKey: "2026-11-05", timeZoneID: "America/Edmonton", durationSeconds: 1800, distanceMeters: 5000,
                energyKcal: 300))
        ctx.insert(
            WeeklyReview(
                weekStartKey: "2026-11-01", weekEndKey: "2026-11-07", timeZoneID: "America/Edmonton",
                unlockedAt: now, moreOfThisText: "walks", moreOfThisTargetStartKey: "2026-11-08",
                moreOfThisTargetEndKey: "2026-11-14"))
        ctx.insert(
            WeeklyIntention(
                sourceSundayKey: "2026-11-08", targetStartKey: "2026-11-09", targetEndKey: "2026-11-15",
                text: "call mum", category: "goal"))
        ctx.insert(
            ImportRecord(
                sourceIdentityHash: "h", importedAt: now, sourceArchiveHash: "ah", targetDateKey: "2026-01-02",
                sourceTimestamp: now, sectionIndex: 0))
        try ctx.save()

        let reader = ModelContext(container)
        let entry = try #require(try reader.fetch(FetchDescriptor<DailyEntry>()).first)
        #expect(entry.dateKey == "2026-11-05" && entry.dayScore == 4)
        #expect(entry.moodIDs == ["happy", "tired"] && entry.tagIDs == [tagID])
        #expect(entry.smileAnswer == "tea")
        #expect(try reader.fetch(FetchDescriptor<AppSettings>()).count == 1)
        #expect(try reader.fetch(FetchDescriptor<PromptAssignment>()).first?.promptID == "p1")
        #expect(try reader.fetch(FetchDescriptor<SchemaV1.Tag>()).first?.name == "run")
        let att = try #require(try reader.fetch(FetchDescriptor<SchemaV1.Attachment>()).first)
        #expect(att.pixelSize == PixelSize(width: 3, height: 4))
        let w = try #require(try reader.fetch(FetchDescriptor<WorkoutSnapshot>()).first)
        #expect(w.healthKitUUID == wid && w.distanceMeters == 5000)
        let r = try #require(try reader.fetch(FetchDescriptor<WeeklyReview>()).first)
        #expect(r.moreOfThisTargetEndKey == "2026-11-14" && r.narrativeJSON == nil)
        let i = try #require(try reader.fetch(FetchDescriptor<WeeklyIntention>()).first)
        #expect(i.targetStartKey == "2026-11-09" && i.followUpSkipped == false)
        #expect(try reader.fetch(FetchDescriptor<ImportRecord>()).first?.sectionIndex == 0)
    }

    @Test("two DailyEntry with the same dateKey collapse to one row")
    func uniqueUpsert() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        ctx.insert(
            DailyEntry(dateKey: "2026-11-05", originalTimeZoneID: "UTC", text: "first", createdAt: t, updatedAt: t))
        ctx.insert(
            DailyEntry(dateKey: "2026-11-05", originalTimeZoneID: "UTC", text: "second", createdAt: t, updatedAt: t))
        try ctx.save()

        let reader = ModelContext(container)  // keep alive: models read through a deallocated context are invalid
        let rows = try reader.fetch(FetchDescriptor<DailyEntry>())
        #expect(rows.count == 1)
        // Which insert's values survive is not stable across runs, so JournalStore must
        // fetch-or-create and never rely on duplicate inserts.
    }
}
