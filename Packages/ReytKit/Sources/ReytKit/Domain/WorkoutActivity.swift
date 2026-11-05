import Foundation

/// The activity kinds be reyt distinguishes. HealthKit's activity type is mapped onto this at the boundary (A6);
/// the stored `WorkoutSnapshot.activityType` is the stable lowercase `id`. Anything unrecognised is `.other`.
public enum WorkoutActivity: String, CaseIterable, Sendable {
    case running, walking, hiking, cycling, swimming, strength, yoga, pilates, rowing, elliptical, hiit, dance, other

    /// Which HealthKit distance quantity carries this activity's distance, if it has one.
    public enum DistanceKind: Sendable, Equatable { case walkingRunning, cycling, swimming }

    /// Total over any stored string: unknown or future ids become `.other`.
    public init(id: String) { self = WorkoutActivity(rawValue: id) ?? .other }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .running: "running"
        case .walking: "walking"
        case .hiking: "hiking"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .strength: "strength"
        case .yoga: "yoga"
        case .pilates: "pilates"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .hiit: "interval training"
        case .dance: "dance"
        case .other: "workout"
        }
    }

    public var distanceKind: DistanceKind? {
        switch self {
        case .running, .walking, .hiking: .walkingRunning
        case .cycling: .cycling
        case .swimming: .swimming
        default: nil
        }
    }
}

/// Which civil day a workout belongs to: the day it started in the zone it happened in. Samples carry that zone
/// in `HKMetadataKeyTimeZone` when the source sets it; many sources (COROS, Strava) do not, so the device's
/// current zone is the fallback and `timeZoneID` is nil to record that it was assumed.
public enum WorkoutDay {
    public static func resolve(
        start: Date, metadataTimeZoneID: String?, deviceTimeZone: TimeZone
    ) -> (dateKey: DateKey, timeZoneID: String?) {
        var calendar = Calendar(identifier: .gregorian)
        if let id = metadataTimeZoneID, let zone = TimeZone(identifier: id) {
            calendar.timeZone = zone
            return (DateKey(date: start, calendar: calendar), id)
        }
        calendar.timeZone = deviceTimeZone
        return (DateKey(date: start, calendar: calendar), nil)
    }
}
