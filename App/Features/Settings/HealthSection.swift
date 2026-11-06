import ReytKit
import SwiftData
import SwiftUI

/// Whether be reyt has asked to read workouts, and a button for the first ask. iOS never tells an app that read
/// access was denied, so there is nothing more to say than "asked".
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
                SettingsRowLabel(title: Copy.Health.unavailable, icon: "waveform.path.ecg", wrapping: true)
            case .notAsked:
                Button {
                    Task { await health.requestAccess() }
                } label: {
                    SettingsAction(title: Copy.Health.allow)
                }
                .accessibilityHint(Copy.Health.allowHint)
            case .asked:
                SettingsRowLabel(title: Copy.Health.asked, icon: "waveform.path.ecg", wrapping: true)
                if health.hasSynced, sample.isEmpty {
                    SettingsNote(text: Copy.Health.nothingFound)
                }
            }
        } header: {
            SettingsHeader(Copy.Health.section)
        }
        .settingsRows()
        .task { await health.refreshAccess() }
    }
}
