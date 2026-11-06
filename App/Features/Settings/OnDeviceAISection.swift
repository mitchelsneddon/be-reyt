import ReytKit
import SwiftUI

/// Whether Apple's on-device model can write reflections right now, in plain words.
struct OnDeviceAISection: View {
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 30
    @State private var status = OnDeviceReflectionGenerator.unavailability(of: .default)

    var body: some View {
        Section {
            if status == nil {
                SettingsRowLabel(title: Copy.Settings.aiRow, icon: "sparkles", value: text, dot: Palette.ok)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRowLabel(title: Copy.Settings.aiRow, icon: "sparkles")
                    Text(text)
                        .brFont(.rowWrapping)
                        .foregroundStyle(Palette.ink2)
                        .padding(.leading, min(tileSide, 44) + 12)
                        .padding(.bottom, 13)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            SettingsHeader(Copy.Settings.aiSection)
        }
        .settingsRows()
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
