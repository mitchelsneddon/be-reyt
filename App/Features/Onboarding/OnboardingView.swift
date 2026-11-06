import SwiftUI

/// Placeholder cover content until the real step screens land.
struct OnboardingView: View {
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Text(name)
                .brFont(.bodyItalic)
                .foregroundStyle(Palette.ink)
            Button(Copy.Onboarding.continueButton) { model.advance() }
                .brFont(.body)
                .frame(minWidth: 44, minHeight: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }

    private var name: String {
        switch model.step {
        case .reminder: Copy.Onboarding.stepReminder
        case .workouts: Copy.Onboarding.stepWorkouts
        case .backups: Copy.Onboarding.stepBackups
        }
    }
}
