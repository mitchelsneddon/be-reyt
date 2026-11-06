import ReytKit
import SwiftData
import SwiftUI

/// The day's workouts as quiet cards after the photo strip. Nothing at all on a day without workouts, and
/// workouts never make a day count as having an entry. Duplicates from several sources show once.
struct WorkoutSection: View {
    @Query private var records: [WorkoutSnapshot]

    init(dateKey: DateKey) {
        let key = dateKey.string
        _records = Query(
            filter: #Predicate<WorkoutSnapshot> { $0.dateKey == key },
            sort: [SortDescriptor(\WorkoutSnapshot.start), SortDescriptor(\WorkoutSnapshot.healthKitUUID)])
    }

    private var groups: [WorkoutGroup] { WorkoutDedupe.collapse(records.map(WorkoutSnapshotValue.init)) }

    var body: some View {
        let groups = groups
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.Workouts.title).font(.footnote).foregroundStyle(Palette.ink2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(groups) { WorkoutCard(workout: $0.representative) }
            }
        }
    }
}

struct WorkoutCard: View {
    let workout: WorkoutSnapshotValue

    private var activity: WorkoutActivity { WorkoutActivity(id: workout.activityType) }
    private var duration: String { Copy.Workouts.duration(seconds: workout.durationSeconds) }
    private var distance: String? {
        guard let meters = workout.distanceMeters, meters > 0 else { return nil }
        return Copy.Workouts.distance(meters: meters, swimming: activity == .swimming)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: activity))
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName).font(.body).foregroundStyle(Palette.ink)
                Text([Optional(duration), distance].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Workouts.cardLabel(name: activity.displayName, duration: duration, distance: distance))
    }

    static func symbol(for activity: WorkoutActivity) -> String {
        switch activity {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .hiit: "figure.highintensity.intervaltraining"
        case .dance: "figure.dance"
        case .other: "figure.mixed.cardio"
        }
    }
}
