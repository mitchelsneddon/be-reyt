import Foundation
import SwiftData
import Testing

@testable import ReytKit

private func value(
    _ id: String, source: String = "COROS", type: String = "running", start: Double, minutes: Double
) -> WorkoutSnapshotValue {
    WorkoutSnapshotValue(
        healthKitUUID: UUID(uuidString: id)!, sourceName: source, activityType: type,
        start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: start + minutes * 60),
        durationSeconds: minutes * 60)
}

private let id1 = "00000000-0000-0000-0000-000000000001"
private let id2 = "00000000-0000-0000-0000-000000000002"
private let id3 = "00000000-0000-0000-0000-000000000003"

@Suite("WorkoutDedupe")
struct WorkoutDedupeTests {
    @Test("the same run from COROS and Strava is one group, represented by COROS")
    func corosAndStrava() {
        // Strava's UUID sorts first, so only the source preference can pick COROS.
        let strava = value(id1, source: "Strava", start: 1000, minutes: 76)
        let coros = value(id2, source: "COROS", start: 1000, minutes: 76)
        let groups = WorkoutDedupe.collapse([strava, coros])
        #expect(groups.count == 1)
        #expect(groups[0].representative.sourceName == "COROS")
        #expect(groups[0].members.count == 2)
    }

    @Test("the earliest start wins over source preference")
    func earliestStart() {
        let strava = value(id1, source: "Strava", start: 1000, minutes: 60)
        let coros = value(id2, source: "COROS", start: 1060, minutes: 60)
        let groups = WorkoutDedupe.collapse([coros, strava])
        #expect(groups.count == 1)
        #expect(groups[0].representative.healthKitUUID == strava.healthKitUUID)
    }

    @Test("with equal start and source preference the lower UUID string wins")
    func uuidTieBreak() {
        let a = value(id2, source: "COROS", start: 1000, minutes: 30)
        let b = value(id1, source: "Garmin", start: 1000, minutes: 30)
        #expect(WorkoutDedupe.collapse([a, b])[0].representative.healthKitUUID == b.healthKitUUID)
    }

    @Test("two different runs on the same day are two groups")
    func twoRuns() {
        let morning = value(id1, start: 0, minutes: 45)
        let evening = value(id2, start: 10 * 3600, minutes: 45)
        let groups = WorkoutDedupe.collapse([evening, morning])
        #expect(groups.map(\.representative.healthKitUUID) == [morning.healthKitUUID, evening.healthKitUUID])
    }

    @Test("same activity with 50 percent overlap is two groups, 80 percent is one")
    func overlapThreshold() {
        let long = value(id1, start: 0, minutes: 60)
        #expect(WorkoutDedupe.collapse([long, value(id2, start: 30 * 60, minutes: 60)]).count == 2)
        // The shorter one (40 min) is 100 percent inside the longer: one group.
        #expect(WorkoutDedupe.collapse([long, value(id2, start: 10 * 60, minutes: 40)]).count == 1)
        // 48 of the shorter 60 minutes overlap is exactly 80 percent.
        #expect(WorkoutDedupe.collapse([long, value(id2, start: 12 * 60, minutes: 60)]).count == 1)
        #expect(WorkoutDedupe.collapse([long, value(id2, start: 13 * 60, minutes: 60)]).count == 2)
    }

    @Test("different activities that overlap stay separate")
    func differentActivity() {
        let run = value(id1, type: "running", start: 0, minutes: 60)
        let ride = value(id2, type: "cycling", start: 0, minutes: 60)
        #expect(WorkoutDedupe.collapse([run, ride]).count == 2)
    }

    @Test("empty in, empty out; every input appears in exactly one group")
    func partition() {
        #expect(WorkoutDedupe.collapse([]).isEmpty)
        let all = [
            value(id1, start: 0, minutes: 60), value(id2, source: "Strava", start: 0, minutes: 60),
            value(id3, start: 9000, minutes: 20),
        ]
        let groups = WorkoutDedupe.collapse(all)
        #expect(groups.flatMap(\.members).count == 3)
        #expect(Set(groups.flatMap(\.members).map(\.healthKitUUID)).count == 3)
    }
}

@Suite("WorkoutActivity and WorkoutDay")
struct WorkoutActivityTests {
    @Test("mapping is total: unknown ids become other, every case round-trips with a name")
    func total() {
        #expect(WorkoutActivity(id: "underwater-basket-weaving") == .other)
        #expect(WorkoutActivity(id: "") == .other)
        for activity in WorkoutActivity.allCases {
            #expect(WorkoutActivity(id: activity.id) == activity)
            #expect(!activity.displayName.isEmpty)
        }
        #expect(WorkoutActivity.running.distanceKind == .walkingRunning)
        #expect(WorkoutActivity.cycling.distanceKind == .cycling)
        #expect(WorkoutActivity.swimming.distanceKind == .swimming)
        #expect(WorkoutActivity.yoga.distanceKind == nil)
    }

    // 2026-11-03 20:00 UTC is 2026-11-04 01:30 in Kolkata (UTC+5:30, no DST): the two zones disagree on the day.
    private let start = Date(timeIntervalSince1970: 1_793_736_000)

    @Test("the metadata zone decides the day, and is recorded")
    func metadataZone() {
        let r = WorkoutDay.resolve(
            start: start, metadataTimeZoneID: "Asia/Kolkata", deviceTimeZone: TimeZone(identifier: "UTC")!)
        #expect(r.dateKey == DateKey("2026-11-04"))
        #expect(r.timeZoneID == "Asia/Kolkata")
    }

    @Test("without metadata the device zone decides the day and no zone is recorded")
    func deviceZone() {
        let r = WorkoutDay.resolve(
            start: start, metadataTimeZoneID: nil, deviceTimeZone: TimeZone(identifier: "UTC")!)
        #expect(r.dateKey == DateKey("2026-11-03"))
        #expect(r.timeZoneID == nil)
    }

    @Test("an unknown zone id falls back to the device zone")
    func badZone() {
        let r = WorkoutDay.resolve(
            start: start, metadataTimeZoneID: "Not/AZone", deviceTimeZone: TimeZone(identifier: "UTC")!)
        #expect(r.dateKey == DateKey("2026-11-03"))
        #expect(r.timeZoneID == nil)
    }
}

@Suite("Workout store sync operations")
struct WorkoutStoreTests {
    private func makeStore() throws -> (JournalStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (
            JournalStore(modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) }), container
        )
    }

    private func input(_ n: Int) -> WorkoutInput {
        WorkoutInput(
            healthKitUUID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, sourceName: "COROS",
            activityType: "running", start: Date(timeIntervalSince1970: Double(n) * 1000),
            end: Date(timeIntervalSince1970: Double(n) * 1000 + 600), dateKey: DateKey("2026-11-02")!,
            durationSeconds: 600, distanceMeters: 1000)
    }

    @Test("a large batch writes in full and re-upserting the identical batch is a no-op")
    func identicalBatch() async throws {
        let (store, container) = try makeStore()
        let batch = (1...600).map(input)
        let first = try await store.upsertWorkouts(batch)
        #expect(first.dirty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSnapshot>()) == 600)
        let second = try await store.upsertWorkouts(batch)
        #expect(second.isEmpty)
    }

    @Test("prune deletes snapshots not in the returned set and reports dirty")
    func prune() async throws {
        let (store, container) = try makeStore()
        let batch = (1...5).map(input)
        _ = try await store.upsertWorkouts(batch)
        let keep = Set(batch.prefix(2).map(\.healthKitUUID))
        let effect = try await store.pruneWorkouts(keeping: keep)
        #expect(effect.dirty)
        let left = try ModelContext(container).fetch(FetchDescriptor<WorkoutSnapshot>())
        #expect(Set(left.map(\.healthKitUUID)) == keep)
        #expect(try await store.pruneWorkouts(keeping: keep).isEmpty)
    }

    @Test("prune and the read-only flag: a read-only store refuses to prune")
    func pruneReadOnly() async throws {
        let (store, _) = try makeStore()
        await store.setReadOnly(true)
        #expect(await store.isReadOnly)
        await #expect(throws: JournalStoreError.readOnly) { try await store.pruneWorkouts(keeping: []) }
    }
}
