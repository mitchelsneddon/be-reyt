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
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Workouts.activitiesTitle)
                VStack(spacing: 10) {
                    ForEach(groups) { WorkoutCard(workout: $0.representative) }
                }
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

    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = 22

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.symbol(for: activity))
                .resizable().scaledToFit()
                .frame(width: min(glyphSide, 34), height: min(glyphSide, 34))
                .foregroundStyle(Palette.accent)
                .frame(width: min(tileSide, 64), height: min(tileSide, 64))
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName).brFont(.cardTitle).foregroundStyle(Palette.ink)
                Text([Optional(duration), distance].compactMap { $0 }.joined(separator: " · "))
                    .brFont(.label).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Copy.Workouts.startTime(workout.start))
                .brFont(.captionItalic).foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 2)
        .cardSurface(padding: 14)
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
