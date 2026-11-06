import Foundation
import SwiftData
import Testing

@testable import ReytKit

private let week = DateKey("2026-11-01")!
private let tue = DateKey("2026-11-03")!
private let wed = DateKey("2026-11-04")!
private let thu = DateKey("2026-11-05")!

private func day(_ key: DateKey, _ text: String) -> ReflectionInput.Day {
    ReflectionInput.Day(
        dateKey: key, text: text, smileAnswer: nil, rotatingPrompt: nil, rotatingAnswer: nil, score: nil,
        moodIDs: [])
}

private func input(_ days: [ReflectionInput.Day]) -> ReflectionInput {
    ReflectionInput(weekStart: week, days: days, intention: nil, followUps: [], workouts: [])
}

private func content(
    overview: String = "a steady week.", highlights: [WeeklyReflectionContent.Point] = [],
    difficult: [WeeklyReflectionContent.Point] = [], themes: [WeeklyReflectionContent.Theme] = [],
    questions: [String] = []
) -> WeeklyReflectionContent {
    WeeklyReflectionContent(
        overview: overview, highlights: highlights, difficult: difficult, themes: themes, questions: questions)
}

private func reasons(_ v: ReflectionValidation) -> [String] {
    if case .invalid(let r) = v { return r }
    return []
}

@Suite("ReflectionValidator")
struct ReflectionValidatorTests {
    private let base = input([day(tue, "ran my 5k by the river."), day(wed, "long day at work.")])

    @Test("a grounded narrative is valid and dates are normalised")
    func valid() {
        let c = content(
            highlights: [.init(text: "your 5k by the river", dateKeys: [tue, tue])],
            themes: [.init(title: "being outside", summary: "the river came up.", dateKeys: [wed, tue])],
            questions: ["what made the river feel good?"])
        guard case .valid(let out) = ReflectionValidator.validate(c, against: base) else {
            Issue.record("expected valid")
            return
        }
        #expect(out.highlights[0].dateKeys == [tue])
        #expect(out.themes[0].dateKeys == [tue, wed])
    }

    @Test("a date outside the week is rejected")
    func unknownDate() {
        let c = content(highlights: [.init(text: "x", dateKeys: [DateKey("2026-11-09")!])])
        #expect(!reasons(ReflectionValidator.validate(c, against: base)).isEmpty)
    }

    @Test("a day in the week without content is rejected")
    func emptyDay() {
        let c = content(highlights: [.init(text: "x", dateKeys: [thu])])
        #expect(reasons(ReflectionValidator.validate(c, against: base)).contains { $0.contains("2026-11-05") })
    }

    @Test("a theme with no supporting date is rejected")
    func themeNeedsDate() {
        let c = content(themes: [.init(title: "t", summary: "s", dateKeys: [])])
        #expect(!reasons(ReflectionValidator.validate(c, against: base)).isEmpty)
    }

    @Test("three questions are rejected, two are fine")
    func questions() {
        #expect(!reasons(ReflectionValidator.validate(content(questions: ["a?", "b?", "c?"]), against: base)).isEmpty)
        guard case .valid = ReflectionValidator.validate(content(questions: ["a?", "b?"]), against: base) else {
            Issue.record("two questions should be valid")
            return
        }
    }

    @Test("a number the person never wrote is rejected")
    func invented() {
        let c = content(overview: "you scored 4 on three days.")
        #expect(reasons(ReflectionValidator.validate(c, against: base)).contains { $0.contains("number 4") })
    }

    @Test("a number that appears inside the journal is accepted, a longer run does not vouch for a shorter one")
    func numerals() {
        guard case .valid = ReflectionValidator.validate(content(overview: "your 5k felt good."), against: base)
        else {
            Issue.record("5k was written")
            return
        }
        let other = input([day(tue, "ran 15 km.")])
        #expect(!reasons(ReflectionValidator.validate(content(overview: "your 5 km run."), against: other)).isEmpty)
    }

    @Test("an empty or blank overview is rejected")
    func emptyOverview() {
        #expect(!reasons(ReflectionValidator.validate(content(overview: "  \n "), against: base)).isEmpty)
    }

    @Test("overlong text is rejected")
    func tooLong() {
        let c = content(overview: String(repeating: "a", count: ReflectionValidator.maxOverviewLength + 1))
        #expect(!reasons(ReflectionValidator.validate(c, against: base)).isEmpty)
    }
}

@Suite("ReflectionSanitiser")
struct ReflectionSanitiserTests {
    private let base = input([
        day(tue, "a long walk by the river. coffee with a friend."),
        day(wed, "a hard long day at work. a walk by the river."),
    ])
    private func run(_ c: WeeklyReflectionContent) -> WeeklyReflectionContent {
        ReflectionSanitiser.sanitise(c, against: base)
    }

    @Test("a theme citing one day is dropped, two days is kept")
    func singleDayTheme() {
        let one = WeeklyReflectionContent.Theme(title: "walk", summary: "s", dateKeys: [tue, tue])
        let two = WeeklyReflectionContent.Theme(title: "river", summary: "s", dateKeys: [tue, wed])
        #expect(run(content(themes: [one, two])).themes.map(\.title) == ["river"])
    }

    @Test("a theme whose second day is not a valid day is dropped")
    func themeInvalidSecondDay() {
        let t = WeeklyReflectionContent.Theme(title: "t", summary: "s", dateKeys: [tue, thu])
        #expect(run(content(themes: [t])).themes.isEmpty)
    }

    @Test("points with no or invalid dates are dropped, invalid dates are removed from kept points")
    func pointDates() {
        let c = content(
            highlights: [
                .init(text: "none", dateKeys: []), .init(text: "bad", dateKeys: [thu]),
                .init(text: "river run", dateKeys: [tue, thu]),
            ],
            difficult: [
                .init(text: "outside", dateKeys: [DateKey("2026-11-09")!]), .init(text: "work", dateKeys: [wed]),
            ])
        let out = run(c)
        #expect(out.highlights == [.init(text: "river run", dateKeys: [tue])])
        #expect(out.difficult.map(\.text) == ["work"])
    }

    @Test("empty points are dropped and text is trimmed")
    func trimming() {
        let out = run(
            content(
                overview: "  hi \n",
                highlights: [.init(text: " \n", dateKeys: [tue]), .init(text: " river ", dateKeys: [tue])]))
        #expect(out.overview == "hi")
        #expect(out.highlights.map(\.text) == ["river"])
    }

    @Test("questions get a question mark, empty ones are dropped")
    func questions() {
        #expect(
            run(content(questions: ["what stood out", "  ", "and the river?"])).questions == [
                "what stood out?", "and the river?",
            ])
    }

    @Test("near-identical highlights on the same single day collapse, different days and different text stay")
    func dedupe() {
        let c = content(highlights: [
            .init(text: "a long walk by the river", dateKeys: [tue]),
            .init(text: "a long walk by the river.", dateKeys: [tue]),
            .init(text: "coffee with a friend", dateKeys: [tue]),
            .init(text: "a long walk by the river", dateKeys: [wed]),
        ])
        #expect(run(c).highlights.count == 3)
    }

    @Test("an empty overview survives sanitising and still fails validation, numerals still fail")
    func stillFatal() {
        let empty = run(content(overview: "  "))
        #expect(!reasons(ReflectionValidator.validate(empty, against: base)).isEmpty)
        let numeric = run(content(overview: "you scored 4."))
        #expect(!reasons(ReflectionValidator.validate(numeric, against: base)).isEmpty)
    }
}

@Suite("Reflection guards in code")
struct ReflectionGuardTests {
    private static func d(
        _ key: String, _ text: String = "", smile: String? = nil, score: Int? = nil, moods: [String] = []
    ) -> ReflectionInput.Day {
        .init(
            dateKey: DateKey(key)!, text: text, smileAnswer: smile, rotatingPrompt: nil, rotatingAnswer: nil,
            score: score, moodIDs: moods)
    }

    /// The seeded week from the round-1 device runs.
    private let seeded = input([
        d("2026-11-01", "planning the week, a few things to sort out."),
        d("2026-11-02", smile: "found the old cafe still does the good scones"),
        d("2026-11-03", "busy, barely looked up until four", moods: ["tired"]),
        d(
            "2026-11-04", "a slow morning, coffee on the step. long walk after lunch, the light was lovely.",
            smile: "the dog fell asleep on my feet.", moods: ["tired", "happy"]),
        d("2026-11-06", "long lunch with friends", score: 5, moods: ["happy"]),
    ])
    private let k3 = DateKey("2026-11-03")!
    private let k4 = DateKey("2026-11-04")!
    private let k6 = DateKey("2026-11-06")!

    private func run(_ c: WeeklyReflectionContent, _ i: ReflectionInput? = nil) -> WeeklyReflectionContent {
        ReflectionSanitiser.sanitise(c, against: i ?? seeded)
    }

    @Test("tired days do not carry invented difficulty")
    func inventedDifficulty() {
        let out = run(
            content(
                difficult: [
                    .init(text: "tiredness settled through the day, even after movement", dateKeys: [k3, k4]),
                    .init(
                        text: "the weight of tiredness, chosen as a mood, lingered through the morning",
                        dateKeys: [k4]),
                ]))
        #expect(out.difficult.isEmpty)
    }

    @Test("invented heaviness is removed from themes, highlights and the overview")
    func inventedHeaviness() {
        let out = run(
            content(
                overview: "a mostly gentle week. others touched by weariness.",
                highlights: [
                    .init(text: "a slow morning, coffee on the step. the effort of staying present.", dateKeys: [k4])
                ],
                themes: [
                    .init(
                        title: "tired", summary: "some days felt heavy, the effort of staying present",
                        dateKeys: [k3, k4]),
                    .init(title: "slow mornings", summary: "coffee on the step and a long walk.", dateKeys: [k3, k4]),
                ],
                questions: ["what made the walk feel good? what felt heavy?"]))
        #expect(out.overview == "a mostly gentle week.")
        #expect(out.highlights.map(\.text) == ["a slow morning, coffee on the step."])
        #expect(out.themes.map(\.title) == ["slow mornings"])
        #expect(out.questions == ["what made the walk feel good?"])
    }

    @Test("an overview that is only invented heaviness becomes empty so the validator retries")
    func overviewEmptied() {
        let out = run(content(overview: "the week carried a quiet weariness."))
        #expect(out.overview.isEmpty)
        #expect(!reasons(ReflectionValidator.validate(out, against: seeded)).isEmpty)
    }

    @Test("a heaviness word the person wrote is allowed")
    func writtenHeaviness() {
        let i = input([
            Self.d("2026-11-03", "a hard conversation with my manager, leaving me unsure.", moods: ["stressed"])
        ])
        let out = run(
            content(
                overview: "a hard conversation stood out.",
                difficult: [
                    .init(text: "a hard conversation with my manager, leaving me unsure.", dateKeys: [k3])
                ]), i)
        #expect(out.overview == "a hard conversation stood out.")
        #expect(out.difficult.map(\.text) == ["a hard conversation with your manager, leaving you unsure."])
    }

    @Test("difficulty needs a signal: hard mood, low score or a written hard word")
    func difficultySignals() {
        let i = input([
            Self.d("2026-11-03", "the bins went out", moods: ["stressed"]),
            Self.d("2026-11-04", "the bins again", score: 2),
            Self.d("2026-11-05", "the bins and a rough start"),
            Self.d("2026-11-06", "the bins, quietly", moods: ["tired"]),
        ])
        func kept(_ k: String) -> Bool {
            !run(content(difficult: [.init(text: "the bins", dateKeys: [DateKey(k)!])]), i).difficult.isEmpty
        }
        #expect(kept("2026-11-03"))
        #expect(kept("2026-11-04"))
        #expect(kept("2026-11-05"))
        #expect(!kept("2026-11-06"))
    }

    @Test("a point citing the wrong day is re-cited to the day that shows it")
    func recite() {
        let out = run(
            content(
                highlights: [
                    .init(text: "the dog falling asleep on my feet, a gentle pause after a busy start", dateKeys: [k3])
                ]))
        #expect(out.highlights.map(\.dateKeys) == [[k4]])
        #expect(out.highlights.first?.text.contains("your feet") == true)
    }

    @Test("a point that matches no day at all is dropped")
    func noMatch() {
        let out = run(content(highlights: [.init(text: "a quiet night of stargazing", dateKeys: [k6])]))
        #expect(out.highlights.isEmpty)
    }

    @Test("second person replaces my, me, myself, i'm and i've; a leftover standalone i drops the sentence")
    func secondPerson() {
        #expect(
            ReflectionSanitiser.secondPerson("My dog sat on me, and I think it was lovely.") == nil)
        #expect(
            ReflectionSanitiser.secondPerson("My dog sat on me, and it was myself that i\u{2019}m sure of.")
                == "Your dog sat on you, and it was yourself that you're sure of.")
        let out = run(
            content(
                overview: "my week had a long lunch. I thought it was nice.",
                questions: ["what did lunch with friends give me?"]))
        #expect(out.overview == "Your week had a long lunch.".lowercasedFirst)
        #expect(out.questions == ["what did lunch with friends give you?"])
    }
}

extension String {
    fileprivate var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

@Suite("ContextBudget")
struct ContextBudgetTests {
    /// One token per character keeps the arithmetic visible.
    private func budget(_ size: Int) -> ContextBudget {
        ContextBudget(contextSize: size) { $0.count }
    }

    private func segments(_ texts: [String]) -> [ContextBudget.Segment] {
        texts.enumerated().map { i, t in .init(id: "d\(i)", dateKey: week.adding(days: i), text: t) }
    }

    private func plan(_ size: Int, _ texts: [String], fixed: Int = 100) async throws -> ContextBudget.Plan {
        try await budget(size).plan(
            singlePassFixedTokens: fixed, singlePassPrompt: texts.joined(), digestFixedTokens: fixed,
            composeFixedTokens: fixed, segments: segments(texts))
    }

    @Test("a small week is one pass")
    func small() async throws {
        #expect(try await plan(8192, ["a short day", "another"]) == .singlePass)
    }

    @Test("an oversized week digests every day")
    func digests() async throws {
        let texts = (0..<7).map { _ in String(repeating: "word ", count: 200) }
        let p = try await plan(3000, texts)
        guard case .digests(let parts) = p else {
            Issue.record("expected digests, got \(p)")
            return
        }
        #expect(Set(parts.compactMap(\.dateKey)) == Set((0..<7).map { week.adding(days: $0) }))
        #expect(parts.allSatisfy { $0.count == 1 })
    }

    @Test("one giant day is chunked and loses nothing")
    func chunked() async throws {
        let paragraphs = (0..<40).map { "paragraph \($0) " + String(repeating: "x", count: 100) }
        let giant = paragraphs.joined(separator: "\n\n")
        let p = try await plan(3500, [giant, "a small day"])
        guard case .digests(let parts) = p else {
            Issue.record("expected digests, got \(p)")
            return
        }
        let giantParts = parts.filter { $0.segmentID == "d0" }
        #expect(giantParts.count > 1)
        #expect(giantParts.map(\.index) == Array(0..<giantParts.count))
        #expect(giantParts.allSatisfy { $0.count == giantParts.count && $0.text.count <= 3500 - 100 - 400 })
        let joined = giantParts.map(\.text).joined(separator: "\n\n")
        for paragraph in paragraphs { #expect(joined.contains(paragraph)) }
        #expect(parts.contains { $0.segmentID == "d1" && $0.text == "a small day" })
    }

    @Test("one paragraph bigger than a piece is split without losing characters")
    func hugeParagraph() async throws {
        let paragraph = (0..<700).map { "w\($0)" }.joined(separator: " ")
        let p = try await plan(3000, [paragraph])
        guard case .digests(let parts) = p else {
            Issue.record("expected digests, got \(p)")
            return
        }
        #expect(parts.count > 1)
        #expect(parts.map(\.text).joined() == paragraph)
    }

    @Test("a week too large even for digests is too long, never truncated")
    func tooLong() async throws {
        let texts = (0..<7).map { _ in String(repeating: "word ", count: 2000) }
        #expect(try await plan(2000, texts) == .tooLong)
    }

    @Test("fixed overhead that leaves no room is too long")
    func noRoom() async throws {
        #expect(try await plan(500, [String(repeating: "x", count: 900)], fixed: 400) == .tooLong)
    }

    @Test("composeFits reads the real composed prompt")
    func compose() async throws {
        #expect(try await budget(2000).composeFits(fixedTokens: 100, prompt: String(repeating: "x", count: 600)))
        #expect(!(try await budget(2000).composeFits(fixedTokens: 100, prompt: String(repeating: "x", count: 800))))
    }
}

// MARK: Store and coordinator

private struct Harness {
    let container: ModelContainer
    let store: JournalStore

    init() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = JournalStore(
            modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
            timeZone: TimeZone(identifier: "America/Edmonton")!)
    }

    func row() throws -> WeeklyReview? {
        let s = week.string
        return try ModelContext(container).fetch(
            FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })
        ).first
    }

    func fingerprint() async throws -> String {
        try ReviewFingerprint.compute(try await store.reflectionInput(weekStart: week))
    }
}

private actor Calls {
    var count = 0
    var reasons: [[String]] = []
    func record(_ r: [String]) {
        count += 1
        reasons.append(r)
    }
}

private struct FakeGenerator: ReflectionGenerating {
    let calls = Calls()
    var unavailable: ReflectionFailure?
    var results: [WeeklyReflectionContent]
    var beforeReturn: (@Sendable () async -> Void)?
    var failure: (any Error)?

    func unavailability() async -> ReflectionFailure? { unavailable }

    func generate(input: ReflectionInput, facts: WeeklyStats, retryReasons: [String]) async throws
        -> WeeklyReflectionContent
    {
        await calls.record(retryReasons)
        await beforeReturn?()
        if let failure { throw failure }
        let i = await calls.count - 1
        return results[min(i, results.count - 1)]
    }
}

@Suite("Reflection store and coordinator")
struct ReflectionCoordinatorTests {
    private let good = content(highlights: [.init(text: "a quiet day", dateKeys: [tue])])
    private let bad = content(overview: "you scored 7 days.")

    private func seeded() async throws -> Harness {
        let h = try Harness()
        _ = try await h.store.updateEntry(tue, .text("a quiet day by the river."))
        return h
    }

    private func coordinator(_ h: Harness, _ g: FakeGenerator) -> ReflectionCoordinator {
        ReflectionCoordinator(store: h.store, generator: g, promptVersion: 1, osBuild: "27A1")
    }

    @Test("a valid result is saved with fingerprint, version and build, and the revision is untouched")
    func saves() async throws {
        let h = try await seeded()
        let outcome = await coordinator(h, FakeGenerator(results: [good])).run(weekStart: week)
        #expect(outcome == .saved(good))
        let r = try #require(try h.row())
        #expect(r.narrativeJSON != nil)
        #expect(r.inputFingerprint == (try await h.fingerprint()))
        #expect(r.promptVersion == 1)
        #expect(r.osBuild == "27A1")
        #expect(r.generatedAt != nil)
        #expect(r.sourceRevision == 0)
    }

    @Test("an invalid answer is retried once with the reasons, then fails and saves nothing")
    func retriesOnce() async throws {
        let h = try await seeded()
        let g = FakeGenerator(results: [bad, bad, good])
        let outcome = await coordinator(h, g).run(weekStart: week)
        #expect(outcome == .failed(.invalidAnswer))
        #expect(await g.calls.count == 2)
        let reasons = await g.calls.reasons
        #expect(reasons[0].isEmpty)
        #expect(!reasons[1].isEmpty)
        #expect(try h.row()?.narrativeJSON == nil)
    }

    @Test("an invalid first answer then a valid second one is saved")
    func retrySucceeds() async throws {
        let h = try await seeded()
        let g = FakeGenerator(results: [bad, good])
        #expect(await coordinator(h, g).run(weekStart: week) == .saved(good))
        #expect(await g.calls.count == 2)
    }

    @Test("a cancelled attempt is a retryable cancellation, not a model error, and saves nothing")
    func cancelled() async throws {
        let h = try await seeded()
        let g = FakeGenerator(results: [good], failure: CancellationError())
        #expect(await coordinator(h, g).run(weekStart: week) == .failed(.cancelled))
        #expect(!ReflectionFailure.cancelled.isUnavailability)
        #expect(try h.row()?.narrativeJSON == nil)
    }

    @Test("a week with nothing recorded never reaches the generator")
    func emptyWeek() async throws {
        let h = try Harness()
        let g = FakeGenerator(results: [good])
        #expect(await coordinator(h, g).run(weekStart: week) == .failed(.noEntries))
        #expect(await g.calls.count == 0)
    }

    @Test("an unavailable model never generates")
    func unavailable() async throws {
        let h = try await seeded()
        let g = FakeGenerator(unavailable: .modelNotReady, results: [good])
        #expect(await coordinator(h, g).run(weekStart: week) == .failed(.modelNotReady))
        #expect(await g.calls.count == 0)
    }

    @Test("an edit while generating discards the result")
    func editDuringGeneration() async throws {
        let h = try await seeded()
        let store = h.store
        var g = FakeGenerator(results: [good])
        g.beforeReturn = { _ = try? await store.updateEntry(tue, .text("changed my mind about the day.")) }
        #expect(await coordinator(h, g).run(weekStart: week) == .failed(.changedWhileWriting))
        #expect(try h.row()?.narrativeJSON == nil)
    }

    @Test("the store refuses a narrative whose fingerprint no longer matches")
    func storeRefuses() async throws {
        let h = try await seeded()
        let stale = try await h.fingerprint()
        _ = try await h.store.updateEntry(tue, .text("something new."))
        await #expect(throws: JournalStoreError.fingerprintMismatch) {
            try await h.store.saveNarrative(
                weekStart: week, content: good, fingerprint: stale, promptVersion: 1, osBuild: "x")
        }
        #expect(try h.row()?.narrativeJSON == nil)
    }

    @Test("a newer prompt version keeps the stored narrative")
    func promptVersionDoesNotPurge() async throws {
        let h = try await seeded()
        _ = try await h.store.saveNarrative(
            weekStart: week, content: good, fingerprint: try await h.fingerprint(), promptVersion: 1, osBuild: "x")
        #expect(try await h.store.validateNarrative(weekStart: week))
        let stored = try #require(try await h.store.storedNarrative(weekStart: week))
        #expect(stored.content == good)
        #expect(stored.promptVersion == 1)
    }

    @Test("an edit after saving purges the narrative and records why")
    func editPurges() async throws {
        let h = try await seeded()
        _ = try await h.store.saveNarrative(
            weekStart: week, content: good, fingerprint: try await h.fingerprint(), promptVersion: 1, osBuild: "x")
        _ = try await h.store.updateEntry(tue, .text("edited later."))
        #expect(try await h.store.validateNarrative(weekStart: week) == false)
        let stored = try #require(try await h.store.storedNarrative(weekStart: week))
        #expect(stored.content == nil)
        #expect(stored.purgeReason != nil)
    }
}

@Suite("ContextBudget real numbers")
struct ContextBudgetRealNumbersTests {
    @Test("ctx 8192, fixed 1481, prompt 369 tokens is a single pass")
    func singlePass() async throws {
        let budget = ContextBudget(contextSize: 8192) { _ in 369 }
        let plan = try await budget.plan(
            singlePassFixedTokens: 1481, singlePassPrompt: "x", digestFixedTokens: 287, composeFixedTokens: 1600,
            segments: [.init(id: "d", dateKey: nil, text: "x")])
        #expect(plan == .singlePass)
    }
}
