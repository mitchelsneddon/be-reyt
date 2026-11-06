import Foundation
import SwiftData
import Testing

@testable import ReytKit

private func makeStore() throws -> JournalStore {
    let container = try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return JournalStore(
        modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
        timeZone: TimeZone(identifier: "UTC")!)
}

private func day(_ s: String) -> DateKey { DateKey(s)! }

@Suite("History and search")
struct HistoryTests {
    @Test("text is found in each searchable field, ignoring case and diacritics")
    func eachField() async throws {
        let store = try makeStore()
        _ = try await store.updateEntry(day("2026-11-01"), .text("Coffee at the Café"))
        _ = try await store.updateEntry(day("2026-11-02"), .smileAnswer("a CAFÉ with Sam"))
        _ = try await store.updateEntry(day("2026-11-03"), .rotatingAnswer("found a cafe by the river"))
        _ = try await store.saveIntention(sunday: day("2026-11-08"), text: "find a new café", category: nil)
        _ = try await store.saveFollowUp(
            sourceSunday: day("2026-11-08"), writtenOn: day("2026-11-15"), note: "the Café was shut", skipped: false)
        _ = try await store.updateEntry(day("2026-11-04"), .text("nothing relevant"))

        let found = try await store.searchDays(text: "cafe")
        #expect(
            found == [day("2026-11-15"), day("2026-11-08"), day("2026-11-03"), day("2026-11-02"), day("2026-11-01")])
        #expect(try await store.searchDays(text: "CAFÉ") == found)
    }

    @Test("no match returns nothing")
    func noMatch() async throws {
        let store = try makeStore()
        _ = try await store.updateEntry(day("2026-11-01"), .text("hello"))
        #expect(try await store.searchDays(text: "zebra").isEmpty)
    }

    @Test("a day with only a prompt assignment never appears")
    func promptOnly() async throws {
        let store = try makeStore()
        _ = try await store.assignPromptIfNeeded(day("2026-11-02")) { _, _ in
            PromptChoice(id: "p1", text: "what felt easy today?")
        }
        _ = try await store.updateEntry(day("2026-11-01"), .text("real"))
        #expect(try await store.historyDays().map(\.dateKey) == [day("2026-11-01")])
        #expect(try await store.searchDays(text: "easy").isEmpty)
        #expect(try await store.searchDays(text: "").map { $0 } == [day("2026-11-01")])
    }

    @Test("history lists only content days, newest first, and agrees with dayContent")
    func historyOrderAndDefinition() async throws {
        let store = try makeStore()
        _ = try await store.updateEntry(day("2026-10-30"), .text("older"))
        _ = try await store.updateEntry(day("2026-11-04"), .score(.good))
        _ = try await store.updateEntry(day("2026-11-02"), .moods(["happy", "tired"]))
        _ = try await store.updateEntry(day("2026-11-03"), .text("   "))  // blank text is not content
        _ = try await store.addAttachmentRecord(
            id: UUID(), dateKey: day("2026-11-01"), relativePath: "a/b.jpg", uti: "public.jpeg", sha256: "00")

        let days = try await store.historyDays()
        #expect(
            days.map(\.dateKey) == [day("2026-11-04"), day("2026-11-02"), day("2026-11-01"), day("2026-10-30")])
        for d in days { #expect(try await store.dayContent(d.dateKey) == d.content) }
        #expect(days[0].content.dayScore == DayScore.good.rawValue)
        #expect(days[1].content.moodIDs.count == 2)
        #expect(days[2].content.attachmentCount == 1)
    }

    @Test("preview is the first nonblank line, falling back through smile, rotating, plan")
    func preview() {
        func s(_ c: DayContent, plan: String? = nil) -> String {
            DaySummary(dateKey: day("2026-11-01"), content: c, planText: plan).preview
        }
        #expect(s(DayContent(text: "\n  first line \nsecond", smileAnswer: "smile")) == "first line")
        #expect(s(DayContent(text: " ", smileAnswer: "smile one")) == "smile one")
        #expect(s(DayContent(rotatingAnswer: "rot")) == "rot")
        #expect(s(DayContent(hasIntention: true), plan: "book dentist") == "book dentist")
        #expect(s(DayContent(dayScore: 3)) == "")
    }
}
