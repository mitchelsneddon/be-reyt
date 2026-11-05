import Foundation
import SwiftData
import Testing

@testable import ReytKit

private let start = DateKey("2026-01-01")!

/// Every pair of assignments within 14 days of each other (either direction) must differ.
private func repeatsWithinWindow(_ assigned: [DateKey: String]) -> [(DateKey, DateKey, String)] {
    var found: [(DateKey, DateKey, String)] = []
    for (a, idA) in assigned {
        for offset in 1...PromptSelector.window {
            let b = a.adding(days: offset)
            if let idB = assigned[b], idA == idB { found.append((a, b, idA)) }
        }
    }
    return found
}

private func history(_ assigned: [DateKey: String]) -> [PromptHistoryItem] {
    assigned.map { PromptHistoryItem(dateKey: $0.key, promptID: $0.value) }
}

@Suite("PromptCatalog")
struct PromptCatalogTests {
    @Test("the five spec prompts are present verbatim")
    func specPrompts() {
        let texts = Set(PromptCatalog.all.map(\.text))
        for spec in [
            "what’s one thing you handled well today?", "who or what did you appreciate today?",
            "what would you like to give yourself credit for?", "what are you looking forward to?",
            "what helped you get through today?",
        ] {
            #expect(texts.contains(spec), "missing: \(spec)")
        }
    }

    @Test("at least 30 prompts, unique stable IDs, lowercase, ending with a question mark")
    func shape() {
        let all = PromptCatalog.all
        #expect(all.count >= 30)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.text)).count == all.count)
        for p in all {
            #expect(p.text == p.text.lowercased())
            #expect(p.text.hasSuffix("?"))
            #expect(p.id == p.id.lowercased() && !p.id.contains(" "))
        }
    }
}

@Suite("PromptSelector")
struct PromptSelectorTests {
    @Test("365 days with rerolls, imported assignments and backfilled days never repeat within 14 days")
    func noRepeatsOverAYear() {
        let selector = PromptSelector()
        let ids = PromptCatalog.all.map(\.id)
        var assigned: [DateKey: String] = [:]

        // 15 imported assignments scattered 23 days apart, with distinct prompts.
        var imported = Set<DateKey>()
        for i in 0..<15 {
            let day = start.adding(days: 3 + i * 23)
            assigned[day] = ids[(i * 7) % ids.count]
            imported.insert(day)
        }
        #expect(Set(assigned.values).count == 15)

        // Five days skipped by the user, assigned only after the rest of the year.
        let skipped: Set<Int> = [40, 111, 200, 201, 300]
        for offset in 0..<365 where !skipped.contains(offset) {
            let day = start.adding(days: offset)
            if assigned[day] != nil { continue }
            assigned[day] = selector.select(for: day, history: history(assigned)).id
        }
        for offset in skipped.sorted() {
            let day = start.adding(days: offset)
            assigned[day] = selector.select(for: day, history: history(assigned)).id
        }

        // Ten rerolls on non-imported days, run against the full year (so both neighbours constrain them).
        var rerolled = 0
        for offset in stride(from: 17, to: 365, by: 34) where rerolled < 10 {
            let day = start.adding(days: offset)
            if imported.contains(day) { continue }
            let before = assigned[day]
            assigned[day] = selector.reroll(for: day, current: before, history: history(assigned)).id
            #expect(assigned[day] != before)
            rerolled += 1
        }
        #expect(rerolled == 10)
        #expect(assigned.count == 365)
        let bad = repeatsWithinWindow(assigned)
        #expect(bad.isEmpty, "repeats: \(bad.prefix(3))")
    }

    @Test("every catalog prompt appears within 2 x catalog size consecutive days from empty history")
    func coverage() {
        let selector = PromptSelector()
        var assigned: [DateKey: String] = [:]
        for offset in 0..<(2 * PromptCatalog.all.count) {
            let day = start.adding(days: offset)
            assigned[day] = selector.select(for: day, history: history(assigned)).id
        }
        #expect(Set(assigned.values) == Set(PromptCatalog.all.map(\.id)))
    }

    @Test("same inputs give the same output from independent selectors")
    func deterministic() {
        let a = PromptSelector()
        let b = PromptSelector()
        var assigned: [DateKey: String] = [:]
        for offset in 0..<60 {
            let day = start.adding(days: offset)
            let x = a.select(for: day, history: history(assigned))
            let y = b.select(for: day, history: history(assigned))
            #expect(x == y)
            #expect(
                a.reroll(for: day, current: x.id, history: history(assigned))
                    == b.reroll(for: day, current: x.id, history: history(assigned)))
            assigned[day] = x.id
        }
    }

    @Test("selection is pinned to a fixed value, so it cannot drift between launches")
    func pinnedOutput() {
        // FNV-1a("") is the offset basis; SplitMix64 reference value for 0.
        #expect(PromptSelector.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(PromptSelector.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(PromptSelector.splitMix64(0) == 0xe220_a839_7b1d_cdaf)
        // First pick for an empty history is the lowest seeded hash; the same on every run.
        let first = PromptSelector().select(for: start, history: [])
        let expected = PromptCatalog.all.min {
            PromptSelector.splitMix64(PromptSelector.fnv1a($0.id) ^ PromptSelector.seed)
                < PromptSelector.splitMix64(PromptSelector.fnv1a($1.id) ^ PromptSelector.seed)
        }
        #expect(first == expected)
    }

    @Test("backfilling a day looks forward as well as back")
    func looksBothWays() {
        let selector = PromptSelector()
        let later = start.adding(days: 5)
        let laterPick = selector.select(for: later, history: [])
        let backfill = selector.select(for: start, history: [PromptHistoryItem(dateKey: later, promptID: laterPick.id)])
        #expect(backfill.id != laterPick.id)
    }

    @Test("when the window excludes everything, the least recently used prompt is chosen")
    func fallbackLRU() {
        let catalog = (0..<3).map { PromptChoice(id: "p\($0)", text: "q\($0)?") }
        let selector = PromptSelector(catalog: catalog)
        let day = start.adding(days: 20)
        let hist = [
            PromptHistoryItem(dateKey: day.adding(days: -3), promptID: "p0"),
            PromptHistoryItem(dateKey: day.adding(days: -9), promptID: "p1"),
            PromptHistoryItem(dateKey: day.adding(days: -1), promptID: "p2"),
        ]
        #expect(selector.select(for: day, history: hist).id == "p1")
    }

    @Test("reroll moves on to a different prompt and never returns the current one first")
    func rerollDiffers() {
        let selector = PromptSelector()
        let first = selector.select(for: start, history: [])
        let second = selector.reroll(for: start, current: first.id, history: [])
        let third = selector.reroll(for: start, current: second.id, history: [])
        #expect(second.id != first.id)
        #expect(third.id != second.id)
        #expect(third.id != first.id)
    }
}

private struct StoreHarness {
    let container: ModelContainer
    let store: JournalStore
    let reader: ModelContext

    init() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = JournalStore(modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) })
        reader = ModelContext(container)
    }
}

@Suite("Prompt store wiring")
struct PromptStoreTests {
    private let day = DateKey("2026-11-03")!

    @Test("stored wording wins after the catalog wording for that ID changes")
    func storedWordingWins() async throws {
        let h = try StoreHarness()
        let original = PromptChoice(id: "x", text: "original wording?")
        let first = try await h.store.assignPromptIfNeeded(day) { key, hist in
            PromptSelector(catalog: [original]).select(for: key, history: hist)
        }
        #expect(first.choice.text == "original wording?")
        let edited = PromptSelector(catalog: [PromptChoice(id: "x", text: "edited wording?")])
        let again = try await h.store.assignPromptIfNeeded(day) { key, hist in edited.select(for: key, history: hist) }
        #expect(again.choice == original)
        #expect(again.effect.isEmpty)
    }

    @Test("reroll is refused when the rotating answer is nonblank and allowed when blank")
    func rerollRules() async throws {
        let h = try StoreHarness()
        let selector = PromptSelector()
        let first = try await h.store.assignPromptIfNeeded(day) { selector.select(for: $0, history: $1) }.choice
        let reroll: PromptReroll = { selector.reroll(for: $0, current: $1, history: $2) }

        let second = try await h.store.rerollPrompt(day, selector: reroll).choice
        #expect(second.id != first.id)
        let stored = try await h.store.assignPromptIfNeeded(day) { selector.select(for: $0, history: $1) }.choice
        #expect(stored == second)

        _ = try await h.store.updateEntry(day, .rotatingAnswer("an answer"))
        await #expect(throws: JournalStoreError.promptAnswered) {
            try await h.store.rerollPrompt(day, selector: reroll)
        }
        let kept = try await h.store.assignPromptIfNeeded(day) { selector.select(for: $0, history: $1) }.choice
        #expect(kept == second)

        _ = try await h.store.updateEntry(day, .rotatingAnswer("   "))
        let third = try await h.store.rerollPrompt(day, selector: reroll).choice
        #expect(third.id != second.id)
    }

    @Test("an assignment alone is not content; a smile answer alone is")
    func contentRules() async throws {
        let h = try StoreHarness()
        let selector = PromptSelector()
        _ = try await h.store.assignPromptIfNeeded(day) { selector.select(for: $0, history: $1) }
        #expect(try await h.store.dayContent(day).hasUserContent == false)
        _ = try await h.store.updateEntry(day, .smileAnswer("the dog"))
        #expect(try await h.store.dayContent(day).hasUserContent)
        _ = try await h.store.updateEntry(day, .smileAnswer(""))
        #expect(try await h.store.dayContent(day).hasUserContent == false)
    }
}
