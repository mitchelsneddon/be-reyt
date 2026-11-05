import Foundation

/// The fields of a stored workout that display and de-duplication need, detached from SwiftData.
public struct WorkoutSnapshotValue: Sendable, Equatable, Hashable {
    public var healthKitUUID: UUID
    public var sourceName: String
    public var activityType: String
    public var start: Date
    public var end: Date
    public var durationSeconds: Double
    public var distanceMeters: Double?
    public var energyKcal: Double?

    public init(
        healthKitUUID: UUID, sourceName: String, activityType: String, start: Date, end: Date,
        durationSeconds: Double, distanceMeters: Double? = nil, energyKcal: Double? = nil
    ) {
        self.healthKitUUID = healthKitUUID
        self.sourceName = sourceName
        self.activityType = activityType
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.energyKcal = energyKcal
    }

    public init(_ w: WorkoutSnapshot) {
        self.init(
            healthKitUUID: w.healthKitUUID, sourceName: w.sourceName, activityType: w.activityType, start: w.start,
            end: w.end, durationSeconds: w.durationSeconds, distanceMeters: w.distanceMeters,
            energyKcal: w.energyKcal)
    }
}

/// One real-world workout, possibly recorded by several sources.
public struct WorkoutGroup: Sendable, Equatable, Identifiable {
    public let representative: WorkoutSnapshotValue
    /// Every snapshot in the group, representative first.
    public let members: [WorkoutSnapshotValue]
    public var id: UUID { representative.healthKitUUID }
}

/// Display-only duplicate collapse. The same run often arrives from two sources (a watch app and Strava). Every
/// snapshot stays stored, so a deletion in Health still applies to exactly the record it names.
public enum WorkoutDedupe {
    /// Two workouts are the same session when they share an activity type and overlap by at least this fraction
    /// of the shorter one.
    public static let overlapThreshold = 0.8

    public static func collapse(_ workouts: [WorkoutSnapshotValue]) -> [WorkoutGroup] {
        let sorted = workouts.sorted(by: ranksBefore)
        var parent = Array(sorted.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for i in sorted.indices {
            for j in sorted.indices where j > i {
                // Sorted by start: once a later workout starts after this one ends, none further can overlap it.
                if sorted[j].start > sorted[i].end { break }
                if sorted[i].activityType == sorted[j].activityType, overlaps(sorted[i], sorted[j]) {
                    parent[root(j)] = root(i)
                }
            }
        }
        var buckets: [Int: [WorkoutSnapshotValue]] = [:]
        for i in sorted.indices { buckets[root(i), default: []].append(sorted[i]) }
        return buckets.values
            .map { members in
                let ordered = members.sorted(by: ranksBefore)
                return WorkoutGroup(representative: ordered[0], members: ordered)
            }
            .sorted { ranksBefore($0.representative, $1.representative) }
    }

    /// Earliest start first; on a tie a non-Strava source first; then UUID string.
    static func ranksBefore(_ a: WorkoutSnapshotValue, _ b: WorkoutSnapshotValue) -> Bool {
        if a.start != b.start { return a.start < b.start }
        let aStrava = isStrava(a.sourceName)
        let bStrava = isStrava(b.sourceName)
        if aStrava != bStrava { return !aStrava }
        return a.healthKitUUID.uuidString < b.healthKitUUID.uuidString
    }

    private static func isStrava(_ name: String) -> Bool { name.lowercased().contains("strava") }

    static func overlaps(_ a: WorkoutSnapshotValue, _ b: WorkoutSnapshotValue) -> Bool {
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        let shorter = min(a.end.timeIntervalSince(a.start), b.end.timeIntervalSince(b.start))
        // A zero-length workout can only match one that starts at the same instant.
        if shorter <= 0 { return a.start == b.start }
        return overlap >= shorter * overlapThreshold
    }
}
