import CoreLocation
import Foundation
import HealthKit
import OSLog

/// What an expanded activity card shows beyond its stored snapshot: the route and the elevation gain. Read live from
/// Health when the card opens and never stored, so no location data lands in the journal or its backups.
struct WorkoutDetail: Sendable, Equatable {
    struct Point: Sendable, Equatable {
        let latitude: Double
        let longitude: Double
    }

    var route: [Point] = []
    var elevationGainMeters: Double?
}

/// Reads `WorkoutDetail` from Health. Read-only (P4). Route access is asked for the first time a card opens, not up
/// front, so workout sync keeps working for anyone who never opens one.
actor WorkoutDetailReader {
    static let shared = WorkoutDetailReader()

    /// More points than this are thinned evenly; the drawing is a few hundred points wide at most.
    static let maxPoints = 600

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "health")

    /// Tries each workout in a duplicate group in turn (the same run from a watch and from Strava) and returns the
    /// first that has a route, keeping the first elevation gain found.
    func detail(for uuids: [UUID]) async -> WorkoutDetail {
        guard HKHealthStore.isHealthDataAvailable() else { return WorkoutDetail() }
        // Shows the Health sheet the first time only; later calls return at once. HealthKit raises an exception
        // (not a thrown error) unless the route's parent type, workouts, is in the same request.
        try? await healthStore.requestAuthorization(
            toShare: [], read: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()])
        var detail = WorkoutDetail()
        for uuid in uuids {
            guard let workout = await workout(uuid) else { continue }
            if detail.elevationGainMeters == nil,
                let gain = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(
                    for: .meter()),
                gain > 0
            {
                detail.elevationGainMeters = gain
            }
            if detail.route.isEmpty { detail.route = await route(of: workout) }
            if !detail.route.isEmpty, detail.elevationGainMeters != nil { break }
        }
        return detail
    }

    private func workout(_ uuid: UUID) async -> HKWorkout? {
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: uuid))], sortDescriptors: [], limit: 1)
        return try? await query.result(for: healthStore).first
    }

    // MARK: HealthKit boundary (A6): only plain coordinates leave this function.

    private func route(of workout: HKWorkout) async -> [WorkoutDetail.Point] {
        let routesQuery = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let routes = try? await routesQuery.result(for: healthStore), !routes.isEmpty else { return [] }
        var points: [WorkoutDetail.Point] = []
        do {
            for route in routes {
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: healthStore) {
                    points.append(
                        .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
                }
            }
        } catch {
            logger.info("route read ended: \((error as NSError).code, privacy: .public)")
        }
        return Self.thinned(points)
    }

    static func thinned(_ points: [WorkoutDetail.Point]) -> [WorkoutDetail.Point] {
        guard points.count > maxPoints else { return points }
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { points[Int((Double($0) * step).rounded())] }
    }
}
