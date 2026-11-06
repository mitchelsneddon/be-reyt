import ReytKit
import SwiftData
import SwiftUI

/// Whether be reyt has asked to read workouts, a button for the first ask, and calm guidance for when none show.
/// iOS never tells an app that read access was denied, so the guidance points at the system settings instead.
struct HealthSection: View {
    @Environment(HealthCoordinator.self) private var health
    @Query(HealthSection.anyWorkout) private var sample: [WorkoutSnapshot]

    private static var anyWorkout: FetchDescriptor<WorkoutSnapshot> {
        var descriptor = FetchDescriptor<WorkoutSnapshot>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        Section {
            switch health.access {
            case .unknown:
                EmptyView()
            case .unavailable:
                Text(Copy.Health.unavailable).frame(minHeight: 44, alignment: .leading)
            case .notAsked:
                Text(Copy.Health.notAsked)
                Button(Copy.Health.allow) { Task { await health.requestAccess() } }
                    .accessibilityHint(Copy.Health.allowHint)
                    .frame(minHeight: 44, alignment: .leading)
            case .asked:
                Text(Copy.Health.asked)
                if health.hasSynced, sample.isEmpty {
                    Text(Copy.Health.nothingFound).foregroundStyle(Palette.ink2)
                }
            }
        } header: {
            Text(Copy.Health.section)
        } footer: {
            if health.access != .unavailable { Text(Copy.Health.guidance) }
        }
        .task { await health.refreshAccess() }
    }
}
