import Foundation
import SwiftData
import Testing

@testable import ReytKit

private let sunday8 = DateKey("2026-11-08")!
private let sunday15 = DateKey("2026-11-15")!

private func makeStore() throws -> JournalStore {
    let container = try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return JournalStore(
        modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
        timeZone: TimeZone(identifier: "UTC")!)
}

@Suite("Sunday plan lifecycle")
struct IntentionLifecycleTests {
    @Test("a plan written Sun 8 Nov covers Mon 9 to Sun 15 and nothing else")
    func planCovering() async throws {
        let store = try makeStore()
        _ = try await store.saveIntention(sunday: sunday8, text: "book the dentist", category: "need to do")
        let plans = try await store.intentionPlans()
        #expect(plans.count == 1)
        #expect(plans[0].targetStart == DateKey("2026-11-09")!)
        #expect(plans[0].targetEnd == sunday15)
        for d in 9...15 {
            let day = DateKey("2026-11-\(d < 10 ? "0" : "")\(d)")!
            #expect(IntentionQueries.planCovering(day: day, in: plans)?.sourceSunday == sunday8)
        }
        #expect(IntentionQueries.planCovering(day: sunday8, in: plans) == nil)
        #expect(IntentionQueries.planCovering(day: DateKey("2026-11-16")!, in: plans) == nil)
    }

    @Test("follow-up is due on the target Sunday; a note there counts as content that day only")
    func followUp() async throws {
        let store = try makeStore()
        _ = try await store.saveIntention(sunday: sunday8, text: "book the dentist", category: nil)
        var plans = try await store.intentionPlans()
        #expect(IntentionQueries.followUpDue(on: sunday15, in: plans)?.sourceSunday == sunday8)
        #expect(IntentionQueries.followUpDue(on: sunday8, in: plans) == nil)
        #expect(IntentionQueries.followUpDue(on: DateKey("2026-11-12")!, in: plans) == nil)

        let effect = try await store.saveFollowUp(
            sourceSunday: sunday8, writtenOn: sunday15, note: "booked it", skipped: false)
        #expect(effect.contentChangedDays == [sunday15])
        #expect(try await store.dayContent(sunday15).hasUserContent)
        #expect(try await store.dayContent(sunday15).hasFollowUpNote)
        // 8 Nov's content is still just the plan, untouched by the follow-up.
        let eighth = try await store.dayContent(sunday8)
        #expect(eighth.hasIntention && !eighth.hasFollowUpNote)

        plans = try await store.intentionPlans()
        #expect(plans[0].followUpNote == "booked it")
        #expect(plans[0].followUpWrittenOn == sunday15)
    }

    @Test("skipping records skipped without making the day content")
    func skip() async throws {
        let store = try makeStore()
        _ = try await store.saveIntention(sunday: sunday8, text: "walk more", category: nil)
        _ = try await store.saveFollowUp(sourceSunday: sunday8, writtenOn: sunday15, note: nil, skipped: true)
        let plan = try #require(try await store.intentionPlans().first)
        #expect(plan.followUpSkipped && plan.hasFollowUpResponse)
        #expect(try await store.dayContent(sunday15).hasUserContent == false)
    }

    @Test("editing a past Sunday's plan leaves other Sundays' plans untouched")
    func editPast() async throws {
        let store = try makeStore()
        let sunday1 = DateKey("2026-11-01")!
        _ = try await store.saveIntention(sunday: sunday1, text: "old", category: "goal")
        _ = try await store.saveIntention(sunday: sunday8, text: "newer", category: nil)
        _ = try await store.saveIntention(sunday: sunday1, text: "old, edited", category: nil)
        let plans = try await store.intentionPlans()
        let first = try #require(IntentionQueries.plan(sourcedOn: sunday1, in: plans))
        let second = try #require(IntentionQueries.plan(sourcedOn: sunday8, in: plans))
        #expect(first.text == "old, edited" && first.category == nil)
        #expect(second.text == "newer" && second.category == nil)
        #expect(first.targetEnd == sunday8 && second.targetEnd == sunday15)
    }

    @Test("blank text and no category deletes the plan")
    func clearing() async throws {
        let store = try makeStore()
        _ = try await store.saveIntention(sunday: sunday8, text: "x", category: "goal")
        _ = try await store.saveIntention(sunday: sunday8, text: "  ", category: nil)
        #expect(try await store.intentionPlans().isEmpty)
        #expect(try await store.dayContent(sunday8).hasUserContent == false)
    }

    @Test("blank text with a category keeps the plan; blank plans are never due or covering")
    func blankHelpers() {
        let blank = IntentionPlan(
            sourceSunday: sunday8, targetStart: DateKey("2026-11-09")!, targetEnd: sunday15, text: "",
            followUpSkipped: true)
        #expect(IntentionQueries.planCovering(day: DateKey("2026-11-10")!, in: [blank]) == nil)
        #expect(IntentionQueries.followUpDue(on: sunday15, in: [blank]) == nil)
    }
}
