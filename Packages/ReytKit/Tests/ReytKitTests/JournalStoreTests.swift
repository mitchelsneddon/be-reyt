import Foundation
import SwiftData
import Testing

@testable import ReytKit

private let day = DateKey("2026-11-03")!  // Tuesday, week of Sunday 2026-11-01
private let week = DateKey("2026-11-01")!
private let nextWeek = DateKey("2026-11-08")!

/// In-memory store plus a long-lived reading context (models must not outlive their context).
private struct Harness {
    let container: ModelContainer
    let store: JournalStore
    let reader: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = JournalStore(
            modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
            timeZone: TimeZone(identifier: "America/Edmonton")!)
        reader = ModelContext(container)
    }

    func review(_ weekStart: DateKey) throws -> WeeklyReview? {
        let s = weekStart.string
        return try reader.fetch(FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })).first
    }

    /// A review row holding a narrative whose fingerprint matches the store's current input.
    func seedReview(_ weekStart: DateKey, moreOfThis: String? = nil) async throws {
        let fp = try ReviewFingerprint.compute(try await store.reflectionInput(weekStart: weekStart))
        let w = ModelContext(container)
        w.insert(
            WeeklyReview(
                weekStartKey: weekStart.string, weekEndKey: weekStart.adding(days: 6).string, timeZoneID: "UTC",
                unlockedAt: Date(timeIntervalSince1970: 0), narrativeJSON: "{\"n\":1}", inputFingerprint: fp,
                generatedAt: Date(timeIntervalSince1970: 1), promptVersion: 1, moreOfThisText: moreOfThis))
        try w.save()
    }

    func narrativeIntact(_ weekStart: DateKey) throws -> Bool {
        reader.rollback()
        guard let r = try review(weekStart) else { return false }
        return r.narrativeJSON != nil && r.inputFingerprint != nil && r.generatedAt != nil && r.sourceRevision == 0
    }

    func workout(_ id: UUID, minutes: Double = 10, on key: DateKey = DateKey("2026-11-02")!) -> WorkoutInput {
        WorkoutInput(
            healthKitUUID: id, sourceName: "watch", activityType: "running", start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 700), dateKey: key, durationSeconds: minutes * 60, distanceMeters: 1000)
    }
}

@Suite("DayContent")
struct DayContentTests {
    @Test("pure truth table")
    func truthTable() {
        #expect(!DayContent().hasUserContent)
        #expect(!DayContent(text: "  \n\t ").hasUserContent)
        #expect(!DayContent(smileAnswer: "  ", rotatingAnswer: " ").hasUserContent)
        #expect(DayContent(text: "a").hasUserContent)
        #expect(DayContent(smileAnswer: "tea").hasUserContent)
        #expect(DayContent(rotatingAnswer: "x").hasUserContent)
        #expect(DayContent(dayScore: 3).hasUserContent)
        #expect(DayContent(moodIDs: ["happy"]).hasUserContent)
        #expect(DayContent(attachmentCount: 1).hasUserContent)
        #expect(DayContent(hasIntention: true).hasUserContent)
        #expect(DayContent(hasFollowUpNote: true).hasUserContent)
    }

    @Test("assembled from records: workout-only and prompt-only are not content")
    func notContent() async throws {
        let h = try Harness()
        _ = try await h.store.upsertWorkouts([h.workout(UUID(), on: day)])
        _ = try await h.store.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "p", text: "why?") }
        #expect(try await h.store.dayContent(day).hasUserContent == false)
        #expect(try await h.store.dayContent(day) == DayContent())
    }

    @Test("assembled from records: whitespace text is not content")
    func whitespace() async throws {
        let h = try Harness()
        let effect = try await h.store.updateEntry(day, .text("   \n"))
        #expect(try await h.store.dayContent(day).hasUserContent == false)
        #expect(effect.contentChangedDays.isEmpty)
    }

    @Test("assembled from records: photo, score, mood each count")
    func counts() async throws {
        let h = try Harness()
        let d = (0..<3).map { week.adding(days: $0 + 1) }
        _ = try await h.store.addAttachmentRecord(
            id: UUID(), dateKey: d[0], relativePath: "a.jpg", uti: "public.jpeg", sha256: "x")
        _ = try await h.store.updateEntry(d[1], .score(.good))
        _ = try await h.store.updateEntry(d[2], .moods(["happy"]))
        for k in d { #expect(try await h.store.dayContent(k).hasUserContent, "\(k)") }
    }

    @Test("assembled from records: Sunday intention counts on that Sunday only; follow-up on the day written")
    func intentionAndFollowUp() async throws {
        let h = try Harness()
        let sunday = DateKey("2026-11-08")!
        _ = try await h.store.saveIntention(sunday: sunday, text: "walk more", category: nil)
        #expect(try await h.store.dayContent(sunday).hasUserContent)
        #expect(try await h.store.dayContent(sunday.adding(days: 1)).hasUserContent == false)
        let written = DateKey("2026-11-12")!
        _ = try await h.store.saveFollowUp(sourceSunday: sunday, writtenOn: written, note: "did it", skipped: false)
        #expect(try await h.store.dayContent(written).hasUserContent)
        #expect(try await h.store.dayContent(sunday.adding(days: 3)).hasUserContent == false)
    }
}

@Suite("JournalStore effects")
struct JournalStoreEffectTests {
    @Test("no-op on a missing entry creates nothing")
    func noOpMissing() async throws {
        let h = try Harness()
        for change: EntryChange in [.text(""), .smileAnswer(nil), .score(nil), .moods([])] {
            #expect(try await h.store.updateEntry(day, change) == StoreEffect())
        }
        #expect(try h.reader.fetchCount(FetchDescriptor<DailyEntry>()) == 0)
    }

    @Test("first content and clearing both report the day; entry is created once")
    func firstAndClear() async throws {
        let h = try Harness()
        let first = try await h.store.updateEntry(day, .text("hello"))
        #expect(first.contentChangedDays == [day])
        #expect(first.dirty)
        let second = try await h.store.updateEntry(day, .score(.good))
        #expect(second.contentChangedDays.isEmpty)
        _ = try await h.store.updateEntry(day, .text(""))
        let cleared = try await h.store.updateEntry(day, .score(nil))
        #expect(cleared.contentChangedDays == [day])
        #expect(try h.reader.fetchCount(FetchDescriptor<DailyEntry>()) == 1)
        let e = try #require(try h.reader.fetch(FetchDescriptor<DailyEntry>()).first)
        #expect(e.originalTimeZoneID == "America/Edmonton")
        #expect(e.createdAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test("moods normalise through the catalog")
    func moods() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(day, .moods(["tired", "happy", "tired"]))
        let e = try #require(try h.reader.fetch(FetchDescriptor<DailyEntry>()).first)
        #expect(e.moodIDs == ["happy", "tired"])
        #expect(try await h.store.updateEntry(day, .moods(["happy", "tired"])) == StoreEffect())
    }

    @Test("intention for Sunday 2026-11-08 targets 11-09 to 11-15; non-Sunday rejected; blank deletes")
    func intentionTargets() async throws {
        let h = try Harness()
        let sunday = DateKey("2026-11-08")!
        _ = try await h.store.saveIntention(sunday: sunday, text: "x", category: "health")
        let row = try #require(try h.reader.fetch(FetchDescriptor<WeeklyIntention>()).first)
        #expect(row.targetStartKey == "2026-11-09")
        #expect(row.targetEndKey == "2026-11-15")
        await #expect(throws: JournalStoreError.notASunday) {
            try await h.store.saveIntention(sunday: day, text: "x", category: nil)
        }
        let removed = try await h.store.saveIntention(sunday: sunday, text: " ", category: nil)
        #expect(removed.contentChangedDays == [sunday])
        h.reader.rollback()
        #expect(try h.reader.fetchCount(FetchDescriptor<WeeklyIntention>()) == 0)
    }

    @Test("rerollPrompt refused when answered; allowed and answer untouched when blank")
    func reroll() async throws {
        let h = try Harness()
        let first = try await h.store.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "a", text: "one") }
        #expect(first.choice.id == "a")
        // already assigned: selector must not be consulted again
        let again = try await h.store.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "zzz", text: "no") }
        #expect(again.choice.id == "a")
        #expect(again.effect.isEmpty)
        _ = try await h.store.rerollPrompt(day, candidate: PromptChoice(id: "b", text: "two"))
        h.reader.rollback()
        #expect(try h.reader.fetch(FetchDescriptor<PromptAssignment>()).first?.promptID == "b")
        _ = try await h.store.updateEntry(day, .rotatingAnswer("my answer"))
        await #expect(throws: JournalStoreError.promptAnswered) {
            try await h.store.rerollPrompt(day, candidate: PromptChoice(id: "c", text: "three"))
        }
        h.reader.rollback()
        #expect(try h.reader.fetch(FetchDescriptor<PromptAssignment>()).first?.promptID == "b")
        #expect(try h.reader.fetch(FetchDescriptor<DailyEntry>()).first?.rotatingAnswer == "my answer")
    }

    @Test("readOnly rejects every mutation and allows reads; lifting it restores writes")
    func readOnly() async throws {
        let h = try Harness()
        await h.store.setReadOnly(true)
        let s = h.store
        let sunday = DateKey("2026-11-08")!
        await #expect(throws: JournalStoreError.readOnly) { try await s.updateEntry(day, .text("x")) }
        await #expect(throws: JournalStoreError.readOnly) {
            try await s.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "a", text: "b") }
        }
        await #expect(throws: JournalStoreError.readOnly) {
            try await s.rerollPrompt(day, candidate: PromptChoice(id: "a", text: "b"))
        }
        await #expect(throws: JournalStoreError.readOnly) {
            try await s.saveIntention(sunday: sunday, text: "x", category: nil)
        }
        await #expect(throws: JournalStoreError.readOnly) {
            try await s.saveFollowUp(sourceSunday: sunday, writtenOn: day, note: "n", skipped: false)
        }
        await #expect(throws: JournalStoreError.readOnly) {
            try await s.addAttachmentRecord(id: UUID(), dateKey: day, relativePath: "a", uti: "u", sha256: "h")
        }
        await #expect(throws: JournalStoreError.readOnly) { try await s.deleteAttachmentRecord(id: UUID()) }
        await #expect(throws: JournalStoreError.readOnly) { try await s.upsertWorkouts([h.workout(UUID())]) }
        await #expect(throws: JournalStoreError.readOnly) { try await s.deleteWorkouts(uuids: [UUID()]) }
        #expect(try await s.dayContent(day) == DayContent())
        #expect(try h.reader.fetchCount(FetchDescriptor<DailyEntry>()) == 0)
        await s.setReadOnly(false)
        #expect(try await s.updateEntry(day, .text("x")).dirty)
    }
}

@Suite("Narrative invalidation")
struct NarrativeInvalidationTests {
    enum Writer: CaseIterable, CustomTestStringConvertible {
        case text, smile, rotating, score, moods, intention, followUp, workoutChange, workoutDelete
        var testDescription: String { "\(self)" }
    }

    private let workoutID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private let priorSunday = DateKey("2026-10-25")!

    /// Seeds every model-input source in `week`, then a review row with a matching narrative.
    private func seeded() async throws -> Harness {
        let h = try Harness()
        _ = try await h.store.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "p", text: "what stood out?") }
        _ = try await h.store.updateEntry(day, .text("a"))
        _ = try await h.store.updateEntry(day, .smileAnswer("s"))
        _ = try await h.store.updateEntry(day, .rotatingAnswer("r"))
        _ = try await h.store.updateEntry(day, .score(.okay))
        _ = try await h.store.updateEntry(day, .moods(["happy"]))
        _ = try await h.store.saveIntention(sunday: week, text: "x", category: "health")
        _ = try await h.store.saveIntention(sunday: priorSunday, text: "earlier", category: nil)
        _ = try await h.store.saveFollowUp(
            sourceSunday: priorSunday, writtenOn: week.adding(days: 3), note: "n", skipped: false)
        _ = try await h.store.upsertWorkouts([h.workout(workoutID)])
        try await h.seedReview(week, moreOfThis: "more walks")
        #expect(try h.narrativeIntact(week), "seed must start with an intact narrative")
        return h
    }

    private func perform(_ w: Writer, _ h: Harness) async throws -> StoreEffect {
        let s = h.store
        switch w {
        case .text: return try await s.updateEntry(day, .text("b"))
        case .smile: return try await s.updateEntry(day, .smileAnswer("t"))
        case .rotating: return try await s.updateEntry(day, .rotatingAnswer("q"))
        case .score: return try await s.updateEntry(day, .score(.good))
        case .moods: return try await s.updateEntry(day, .moods(["happy", "tired"]))
        case .intention: return try await s.saveIntention(sunday: week, text: "y", category: "health")
        case .followUp:
            return try await s.saveFollowUp(
                sourceSunday: priorSunday, writtenOn: week.adding(days: 3), note: "m", skipped: false)
        case .workoutChange: return try await s.upsertWorkouts([h.workout(workoutID, minutes: 30)])
        case .workoutDelete: return try await s.deleteWorkouts(uuids: [workoutID])
        }
    }

    @Test("every model-input writer purges the narrative and reports the week", arguments: Writer.allCases)
    func writerPurges(_ w: Writer) async throws {
        let h = try await seeded()
        let effect = try await perform(w, h)
        #expect(effect.revisionBumpedWeeks == [week])
        #expect(effect.dirty)
        h.reader.rollback()
        let r = try #require(try h.review(week))
        #expect(r.narrativeJSON == nil)
        #expect(r.inputFingerprint == nil)
        #expect(r.generatedAt == nil)
        #expect(r.sourceRevision == 1)
        #expect(r.purgeReason == "source changed")
        #expect(r.moreOfThisText == "more walks")
    }

    @Test("an edit in another week leaves this week's narrative alone")
    func otherWeek() async throws {
        let h = try await seeded()
        let effect = try await h.store.updateEntry(DateKey("2026-11-10")!, .text("later"))
        #expect(effect.revisionBumpedWeeks.isEmpty)
        #expect(try h.narrativeIntact(week))
    }

    @Test("no-op writes keep the narrative and bump nothing")
    func noOps() async throws {
        let h = try await seeded()
        let s = h.store
        let noOps: [StoreEffect] = [
            try await s.updateEntry(day, .text("a")),
            try await s.updateEntry(day, .score(.okay)),
            try await s.updateEntry(day, .moods(["happy"])),
            try await s.saveIntention(sunday: week, text: "x", category: "health"),
            try await s.saveFollowUp(
                sourceSunday: priorSunday, writtenOn: week.adding(days: 3), note: "n", skipped: false),
            try await s.upsertWorkouts([h.workout(workoutID)]),
            try await s.deleteWorkouts(uuids: [UUID()]),
        ]
        for e in noOps { #expect(e == StoreEffect()) }
        #expect(try h.narrativeIntact(week))
    }

    @Test("attachment add and delete keep the narrative but flip content and set dirty")
    func attachmentsDontTouchInput() async throws {
        let h = try await seeded()
        let quiet = DateKey("2026-11-06")!
        let id = UUID()
        let added = try await h.store.addAttachmentRecord(
            id: id, dateKey: quiet, relativePath: "p.jpg", uti: "public.jpeg", sha256: "h")
        #expect(added.revisionBumpedWeeks.isEmpty)
        #expect(added.contentChangedDays == [quiet])
        #expect(added.dirty)
        #expect(
            try await h.store.addAttachmentRecord(
                id: id, dateKey: quiet, relativePath: "p.jpg", uti: "public.jpeg", sha256: "h"
            ).isEmpty)
        #expect(try h.narrativeIntact(week))
        let removed = try await h.store.deleteAttachmentRecord(id: id)
        #expect(removed.contentChangedDays == [quiet])
        #expect(removed.revisionBumpedWeeks.isEmpty)
        #expect(try h.narrativeIntact(week))
    }

    @Test("a photo-only day counts as content until its last photo is removed, and refs list the records")
    func photoOnlyDay() async throws {
        let h = try Harness()
        let id = UUID()
        #expect(try await h.store.dayContent(day).hasUserContent == false)
        _ = try await h.store.addAttachmentRecord(
            id: id, dateKey: day, relativePath: "\(id.uuidString.lowercased()).jpg", uti: "public.jpeg", sha256: "h")
        #expect(try await h.store.dayContent(day).hasUserContent)
        #expect(
            try await h.store.attachmentRefs() == [
                AttachmentRef(id: id, relativePath: "\(id.uuidString.lowercased()).jpg")
            ])
        let removed = try await h.store.deleteAttachmentRecord(id: id)
        #expect(removed.contentChangedDays == [day])
        #expect(try await h.store.dayContent(day).hasUserContent == false)
        #expect(try await h.store.attachmentRefs().isEmpty)
    }

    @Test("workout energy change is persisted (dirty) but does not bump")
    func workoutEnergy() async throws {
        let h = try await seeded()
        var w = h.workout(workoutID)
        w.energyKcal = 300
        let effect = try await h.store.upsertWorkouts([w])
        #expect(effect.dirty)
        #expect(effect.revisionBumpedWeeks.isEmpty)
        #expect(try h.narrativeIntact(week))
    }

    @Test("a follow-up moved to another week bumps both weeks")
    func followUpMoves() async throws {
        let h = try await seeded()
        try await h.seedReview(nextWeek)
        let effect = try await h.store.saveFollowUp(
            sourceSunday: priorSunday, writtenOn: nextWeek.adding(days: 1), note: "n", skipped: false)
        #expect(effect.revisionBumpedWeeks == [week, nextWeek])
    }

    @Test("a week with no review row reports no bump")
    func noRow() async throws {
        let h = try Harness()
        #expect(try await h.store.updateEntry(day, .text("a")).revisionBumpedWeeks.isEmpty)
    }
}

@Suite("ReflectionInput and fingerprint")
struct ReflectionInputTests {
    @Test("a text change changes the fingerprint; a promptVersion change does not")
    func fingerprintSensitivity() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(day, .text("a"))
        let f1 = try ReviewFingerprint.compute(try await h.store.reflectionInput(weekStart: week))
        #expect(f1.count == 64)
        #expect(f1 == (try ReviewFingerprint.compute(try await h.store.reflectionInput(weekStart: week))))
        _ = try await h.store.updateEntry(day, .text("b"))
        let f2 = try ReviewFingerprint.compute(try await h.store.reflectionInput(weekStart: week))
        #expect(f1 != f2)

        try await h.seedReview(week)
        let w = ModelContext(h.container)
        let row = try #require(try w.fetch(FetchDescriptor<WeeklyReview>()).first)
        row.promptVersion = 99
        try w.save()
        #expect(try await h.store.validateNarrative(weekStart: week))
        h.reader.rollback()
        #expect(try h.review(week)?.narrativeJSON != nil)
    }

    @Test("input contains exactly the model-input set, with prompt wording resolved")
    func contents() async throws {
        let h = try Harness()
        _ = try await h.store.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "p", text: "what stood out?") }
        _ = try await h.store.updateEntry(day, .text("hello"))
        _ = try await h.store.updateEntry(day, .rotatingAnswer("this"))
        _ = try await h.store.updateEntry(day, .score(.good))
        _ = try await h.store.saveIntention(sunday: week, text: "walk", category: "health")
        _ = try await h.store.upsertWorkouts([h.workout(UUID())])
        _ = try await h.store.addAttachmentRecord(
            id: UUID(), dateKey: DateKey("2026-11-05")!, relativePath: "a", uti: "u", sha256: "h")
        _ = try await h.store.updateEntry(DateKey("2026-11-10")!, .text("outside the week"))
        let input = try await h.store.reflectionInput(weekStart: week)
        #expect(input.days.count == 1)
        let d = try #require(input.days.first)
        #expect(d.text == "hello")
        #expect(d.rotatingPrompt == "what stood out?")
        #expect(d.rotatingAnswer == "this")
        #expect(d.score == 4)
        #expect(input.intention == ReflectionInput.Intention(text: "walk", category: "health"))
        #expect(input.workouts.count == 1)
        #expect(input.workouts.first?.activity == "running")
        #expect(input.workouts.first?.durationSeconds == 600)
        #expect(input.workouts.first?.distanceMeters == 1000)
    }

    @Test("an unanswered prompt is not model input")
    func unansweredPrompt() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(day, .text("hello"))
        let before = try ReviewFingerprint.compute(try await h.store.reflectionInput(weekStart: week))
        _ = try await h.store.assignPromptIfNeeded(day) { _, _ in PromptChoice(id: "p", text: "q") }
        #expect(before == (try ReviewFingerprint.compute(try await h.store.reflectionInput(weekStart: week))))
    }

    @Test("canonical form ignores ordering of moods and workouts")
    func canonical() throws {
        let w1 = ReflectionInput.Workout(dateKey: day, activity: "run", durationSeconds: 1, distanceMeters: nil)
        let w2 = ReflectionInput.Workout(dateKey: day, activity: "walk", durationSeconds: 2, distanceMeters: 5)
        func mkDay(_ moods: [String]) -> ReflectionInput.Day {
            .init(
                dateKey: DateKey("2026-11-03")!, text: "t", smileAnswer: nil, rotatingPrompt: nil, rotatingAnswer: nil,
                score: nil, moodIDs: moods)
        }
        let a = ReflectionInput(
            weekStart: week, days: [mkDay(["a", "b"])], intention: nil, followUps: [], workouts: [w1, w2])
        let b = ReflectionInput(
            weekStart: week, days: [mkDay(["b", "a"])], intention: nil, followUps: [], workouts: [w2, w1])
        #expect(try ReviewFingerprint.compute(a) == ReviewFingerprint.compute(b))
        #expect(a == b)
    }

    @Test("validateNarrative keeps on match and purges on mismatch")
    func validate() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(day, .text("a"))
        try await h.seedReview(week, moreOfThis: "keep me")
        #expect(try await h.store.validateNarrative(weekStart: week))
        #expect(try h.narrativeIntact(week))

        // change the source behind the store's back (no bump), as a restore or bug might
        let w = ModelContext(h.container)
        let e = try #require(try w.fetch(FetchDescriptor<DailyEntry>()).first)
        e.text = "tampered"
        try w.save()
        #expect(try await h.store.validateNarrative(weekStart: week) == false)
        h.reader.rollback()
        let r = try #require(try h.review(week))
        #expect(r.narrativeJSON == nil)
        #expect(r.inputFingerprint == nil)
        #expect(r.moreOfThisText == "keep me")
        #expect(try await h.store.validateNarrative(weekStart: week) == false)
    }

    @Test("validateNarrative does not write in read-only mode")
    func validateReadOnly() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(day, .text("a"))
        try await h.seedReview(week)
        let w = ModelContext(h.container)
        try #require(try w.fetch(FetchDescriptor<DailyEntry>()).first).text = "tampered"
        try w.save()
        await h.store.setReadOnly(true)
        #expect(try await h.store.validateNarrative(weekStart: week) == false)
        h.reader.rollback()
        #expect(try h.review(week)?.narrativeJSON != nil)
    }
}
