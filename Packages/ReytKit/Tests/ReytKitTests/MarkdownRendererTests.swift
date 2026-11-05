import Foundation
import Testing

@testable import ReytKit

private let tagID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let photoID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
private let date = Date(timeIntervalSince1970: 1_700_000_000)

private func entry(
    _ day: String, text: String = "", smile: String? = nil, rotating: String? = nil, score: Int? = nil,
    moods: [String] = [], tags: [UUID] = []
) -> DailyEntryDTO {
    DailyEntryDTO(
        id: UUID(), dateKey: day, originalTimeZoneID: "UTC", text: text, smileAnswer: smile, rotatingAnswer: rotating,
        dayScore: score, moodIDs: moods, tagIDs: tags, createdAt: date, updatedAt: date)
}

private func workout(_ day: String, _ id: String, type: String = "running", start: Double = 1000) -> WorkoutSnapshotDTO
{
    WorkoutSnapshotDTO(
        healthKitUUID: UUID(uuidString: id)!, sourceName: "COROS", activityType: type,
        start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: start + 2700), dateKey: day,
        timeZoneID: nil, durationSeconds: 2700, distanceMeters: 6200, energyKcal: 420)
}

private func data(
    entries: [DailyEntryDTO] = [], attachments: [AttachmentDTO] = [], prompts: [PromptAssignmentDTO] = [],
    intentions: [WeeklyIntentionDTO] = [], reviews: [WeeklyReviewDTO] = [], workouts: [WorkoutSnapshotDTO] = []
) -> ArchiveData {
    ArchiveData(
        entries: entries, tags: [TagDTO(id: tagID, name: "walk 🚶", createdAt: date)], attachments: attachments,
        promptAssignments: prompts, intentions: intentions, reviews: reviews, workouts: workouts, importRecords: [],
        settings: AppSettingsDTO(reminderEnabled: true, reminderHour: 21, includeWorkoutsInExports: false))
}

private let photo = AttachmentDTO(
    id: photoID, entryDateKey: "2026-11-05", relativePath: "00000000-0000-0000-0000-0000000000b1.jpg",
    uti: "public.jpeg", sha256: "x", pixelSize: nil, createdAt: date)

private let plan = WeeklyIntentionDTO(
    sourceSundayKey: "2026-11-01", targetStartKey: "2026-11-02", targetEndKey: "2026-11-08", text: "call mum",
    category: "need-to-do", followUpNote: "called, all good.", followUpWrittenOnKey: "2026-11-08",
    followUpSkipped: false)

private func fullFixture(includeWorkouts: Bool = false) -> [MarkdownRenderer.File] {
    MarkdownRenderer.render(
        data(
            entries: [
                entry(
                    "2026-11-05", text: "café 😊 שלום\n# not a heading\nsecond line", smile: "the dog",
                    rotating: "a quiet cup",
                    score: 4, moods: ["happy", "tired"], tags: [tagID]),
                entry("2026-11-01", text: "sunday"), entry("2026-11-08", text: "follow up day"),
            ], attachments: [photo],
            prompts: [
                PromptAssignmentDTO(
                    dateKey: "2026-11-05", promptID: "p1", promptText: "what felt easy today?", assignedAt: date)
            ], intentions: [plan],
            workouts: [workout("2026-11-05", "00000000-0000-0000-0000-000000000001")]),
        includeWorkouts: includeWorkouts)
}

private func file(_ files: [MarkdownRenderer.File], _ path: String) -> String? {
    files.first { $0.path == path }?.contents
}

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    @Test("a full day renders every labelled section in order, with Unicode untouched")
    func fullDay() throws {
        let day = try #require(file(fullFixture(), "2026-11-05.md"))
        let expected = """
            # thursday, 5 november 2026

            day score: good  
            moods: happy, tired  
            tags: walk 🚶

            café 😊 שלום  
            \\# not a heading  
            second line

            ## what made me smile today?

            the dog

            ## what felt easy today?

            a quiet cup

            ## photos

            ![photo 1](photos/00000000-0000-0000-0000-0000000000b1.jpg)

            """
        #expect(day == expected)
    }

    @Test("plan with its category label, and the follow-up note on the day it was written")
    func planAndFollowUp() throws {
        let sunday = try #require(file(fullFixture(), "2026-11-01.md"))
        #expect(sunday.contains("## plan for the week\n\nneed to do\n\ncall mum"))
        let later = try #require(file(fullFixture(), "2026-11-08.md"))
        #expect(later.contains("## how did that go?\n\nyou planned: call mum\n\ncalled, all good."))
    }

    @Test("a day with only a score has just the heading and the score, nothing empty")
    func scoreOnly() throws {
        let files = MarkdownRenderer.render(data(entries: [entry("2026-11-05", score: 2)]), includeWorkouts: false)
        #expect(file(files, "2026-11-05.md") == "# thursday, 5 november 2026\n\nday score: difficult\n")
    }

    @Test("empty optionals never appear as sections, nil or empty headings")
    func noEmptySections() throws {
        let day = try #require(file(fullFixture(), "2026-11-08.md"))
        for banned in ["nil", "day score", "moods", "tags", "photos", "workouts", "what made me smile"] {
            #expect(!day.contains(banned))
        }
        #expect(!day.contains("## \n"))
    }

    @Test("workouts appear only when included, and the index says which")
    func workoutsToggle() throws {
        let on = fullFixture(includeWorkouts: true)
        let off = fullFixture(includeWorkouts: false)
        let dayOn = try #require(file(on, "2026-11-05.md"))
        #expect(
            dayOn.contains("## workouts\n\nworkouts copied from apple health\n\n- running, 45 min, 6.2 km, 420 kcal"))
        #expect(try #require(file(off, "2026-11-05.md")).contains("workouts") == false)
        #expect(try #require(file(on, "index.md")).contains("workouts are included, copied from apple health."))
        let offIndex = try #require(file(off, "index.md"))
        #expect(offIndex.contains("workouts are not included."))
        #expect(!offIndex.contains("are included"))
    }

    @Test("duplicate workouts from two sources show once")
    func workoutsDeduped() throws {
        let files = MarkdownRenderer.render(
            data(
                entries: [entry("2026-11-05", text: "x")],
                workouts: [
                    workout("2026-11-05", "00000000-0000-0000-0000-000000000001"),
                    workout("2026-11-05", "00000000-0000-0000-0000-000000000002"),
                ]), includeWorkouts: true)
        let day = try #require(file(files, "2026-11-05.md"))
        #expect(day.components(separatedBy: "- running").count == 2)
    }

    @Test("days without content produce no file, including a prompt-only day and a workout-only day")
    func noContentNoFile() {
        let files = MarkdownRenderer.render(
            data(
                entries: [entry("2026-11-04", text: "   \n"), entry("2026-11-06", smile: "")],
                prompts: [
                    PromptAssignmentDTO(dateKey: "2026-11-03", promptID: "p", promptText: "q?", assignedAt: date)
                ],
                workouts: [workout("2026-11-07", "00000000-0000-0000-0000-000000000001")]), includeWorkouts: true)
        #expect(files.map(\.path) == ["index.md"])
        #expect(file(files, "index.md")?.contains("no days to show") == true)
    }

    @Test("the index lists months and links each day file")
    func index() throws {
        let files = MarkdownRenderer.render(
            data(entries: [entry("2026-10-31", text: "a"), entry("2026-11-02", text: "b")]), includeWorkouts: false)
        let index = try #require(file(files, "index.md"))
        #expect(index.contains("## october 2026\n\n- [saturday, 31 october 2026](2026-10-31.md)"))
        #expect(index.contains("## november 2026\n\n- [monday, 2 november 2026](2026-11-02.md)"))
        #expect(index.contains("2 days, 31 october 2026 to 2 november 2026."))
    }

    @Test("a range limits which days are exported")
    func range() throws {
        let a = try #require(DateKey("2026-11-02"))
        let b = try #require(DateKey("2026-11-03"))
        let files = MarkdownRenderer.render(
            data(entries: [
                entry("2026-11-01", text: "a"), entry("2026-11-02", text: "b"), entry("2026-11-04", text: "c"),
            ]),
            includeWorkouts: false, range: a...b)
        #expect(files.map(\.path) == ["index.md", "2026-11-02.md"])
    }

    @Test("quote, fence and leading-space-hash lines are escaped; other text is verbatim")
    func escaping() {
        #expect(MarkdownRenderer.escapeLine("# a") == "\\# a")
        #expect(MarkdownRenderer.escapeLine("  ## a") == "\\  ## a")
        #expect(MarkdownRenderer.escapeLine("> q") == "\\> q")
        #expect(MarkdownRenderer.escapeLine("```swift") == "\\```swift")
        #expect(MarkdownRenderer.escapeLine("mid # hash") == "mid # hash")
        #expect(MarkdownRenderer.escapeLine("עברית 😊") == "עברית 😊")
    }

    @Test("the same input renders byte-identical output")
    func deterministic() {
        #expect(fullFixture(includeWorkouts: true) == fullFixture(includeWorkouts: true))
        let a = fullFixture().map { Data($0.contents.utf8) }
        let b = fullFixture().map { Data($0.contents.utf8) }
        #expect(a == b)
    }

    @Test("weekly more-of-this notes go to their own file, linked from the index")
    func weeklyReviews() throws {
        let review = WeeklyReviewDTO(
            weekStartKey: "2026-11-02", weekEndKey: "2026-11-08", timeZoneID: "UTC", unlockedAt: date,
            sourceRevision: 0,
            narrativeJSON: nil, inputFingerprint: nil, generatedAt: nil, promptVersion: nil, osBuild: nil,
            purgeReason: nil, moreOfThisText: "more walks", moreOfThisTargetStartKey: nil, moreOfThisTargetEndKey: nil)
        let files = MarkdownRenderer.render(
            data(entries: [entry("2026-11-05", text: "x")], reviews: [review]), includeWorkouts: false)
        #expect(file(files, "weekly-reviews.md")?.contains("more of this: more walks") == true)
        #expect(file(files, "index.md")?.contains("(weekly-reviews.md)") == true)
    }
}
