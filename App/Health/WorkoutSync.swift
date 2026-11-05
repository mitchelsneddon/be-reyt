import Foundation
import HealthKit
import OSLog
import ReytKit

/// Reads workouts from Health into `JournalStore`. Read-only: nothing is ever shared back to Health (P4).
/// Anchored sync: each run asks only for what changed since the stored anchor, and the anchor moves forward only
/// after the store writes succeed, so a failed run is simply repeated (upserts are idempotent).
actor WorkoutSync {
    enum Outcome: Equatable, Sendable {
        /// Access has not been asked for, Health is unavailable, or the store is read-only (a restore is running).
        case skipped
        case synced(StoreEffect, returned: Int)
    }

    enum Access: Sendable { case unavailable, notAsked, asked }

    /// A first sync can return thousands of workouts, so writes go in chunks, each its own transaction.
    static let chunkSize = 500

    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
        HKQuantityType(.activeEnergyBurned),
    ]

    private let healthStore = HKHealthStore()
    private let anchors: HealthAnchorStore
    private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "health")

    init(anchors: HealthAnchorStore) { self.anchors = anchors }

    func access() async -> Access {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            let status = try await healthStore.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
            return status == .shouldRequest ? .notAsked : .asked
        } catch {
            return .notAsked
        }
    }

    func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// Incremental sync from the stored anchor.
    func sync(into store: JournalStore) async throws -> Outcome {
        try await run(into: store, pruneUnreturned: false)
    }

    /// After a restore: forget the anchor, read everything, then drop snapshots Health no longer has (deleted since
    /// the backup was made).
    func resyncAfterRestore(into store: JournalStore) async throws -> Outcome {
        anchors.reset()
        return try await run(into: store, pruneUnreturned: true)
    }

    private func run(into store: JournalStore, pruneUnreturned: Bool) async throws -> Outcome {
        guard await access() == .asked, !(await store.isReadOnly) else { return .skipped }
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout()], anchor: anchors.load())
        let result = try await descriptor.result(for: healthStore)

        let deviceZone = TimeZone.current
        let inputs = result.addedSamples.map { Self.input(from: $0, deviceTimeZone: deviceZone) }
        var effect = StoreEffect()
        for start in stride(from: 0, to: inputs.count, by: Self.chunkSize) {
            effect.merge(
                try await store.upsertWorkouts(Array(inputs[start..<min(start + Self.chunkSize, inputs.count)])))
        }
        let deleted = result.deletedObjects.map(\.uuid)
        for start in stride(from: 0, to: deleted.count, by: Self.chunkSize) {
            effect.merge(
                try await store.deleteWorkouts(
                    uuids: Array(deleted[start..<min(start + Self.chunkSize, deleted.count)])))
        }
        // shortcut: iOS does not say whether read access was denied; a denied full sync looks like an empty one.
        // Pruning on an empty result would wipe every restored workout, so an empty result never prunes.
        if pruneUnreturned, !inputs.isEmpty {
            effect.merge(try await store.pruneWorkouts(keeping: Set(inputs.map(\.healthKitUUID))))
        }
        try anchors.save(result.newAnchor)
        logger.info("workout sync: \(inputs.count) added, \(deleted.count) deleted")
        return .synced(effect, returned: inputs.count)
    }

    // MARK: HealthKit boundary (A6): nothing HealthKit leaves this function.

    static func input(from workout: HKWorkout, deviceTimeZone: TimeZone) -> WorkoutInput {
        let activity = activity(for: workout.workoutActivityType)
        let zoneID = workout.metadata?[HKMetadataKeyTimeZone] as? String
        let day = WorkoutDay.resolve(
            start: workout.startDate, metadataTimeZoneID: zoneID, deviceTimeZone: deviceTimeZone)
        return WorkoutInput(
            healthKitUUID: workout.uuid, sourceName: workout.sourceRevision.source.name, activityType: activity.id,
            start: workout.startDate, end: workout.endDate, dateKey: day.dateKey, timeZoneID: day.timeZoneID,
            durationSeconds: workout.duration, distanceMeters: distance(of: workout, for: activity),
            energyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
                .doubleValue(for: .kilocalorie()))
    }

    private static func distance(of workout: HKWorkout, for activity: WorkoutActivity) -> Double? {
        guard let kind = activity.distanceKind else { return nil }
        let identifier: HKQuantityTypeIdentifier =
            switch kind {
            case .walkingRunning: .distanceWalkingRunning
            case .cycling: .distanceCycling
            case .swimming: .distanceSwimming
            }
        // Workouts saved without a builder carry a plain total instead of statistics.
        let quantity = workout.statistics(for: HKQuantityType(identifier))?.sumQuantity() ?? workout.totalDistance
        guard let meters = quantity?.doubleValue(for: .meter()), meters > 0 else { return nil }
        return meters
    }

    static func activity(for type: HKWorkoutActivityType) -> WorkoutActivity {
        switch type {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .cycling, .handCycling: .cycling
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .strength
        case .yoga: .yoga
        case .pilates: .pilates
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .highIntensityIntervalTraining: .hiit
        case .dance, .socialDance, .cardioDance: .dance
        default: .other
        }
    }
}
