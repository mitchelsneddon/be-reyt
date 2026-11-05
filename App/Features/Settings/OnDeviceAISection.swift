import ReytKit
import SwiftUI

/// Whether Apple's on-device model can write reflections right now, in plain words.
struct OnDeviceAISection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = OnDeviceReflectionGenerator.unavailability(of: .default)

    var body: some View {
        Section {
            LabeledContent(Copy.Settings.aiRow) {
                Text(text).multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        } header: {
            Text(Copy.Settings.aiSection)
        } footer: {
            Text(Copy.Settings.aiFooter)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { status = OnDeviceReflectionGenerator.unavailability(of: .default) }
        }
    }

    private var text: String {
        switch status {
        case nil: Copy.Settings.aiAvailable
        case .appleIntelligenceNotEnabled: Copy.Settings.aiTurnOn
        case .modelNotReady: Copy.Settings.aiDownloading
        case .unsupportedLanguage: Copy.Settings.aiLanguage
        default: Copy.Settings.aiNotSupported
        }
    }
}
