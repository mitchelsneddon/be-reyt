import SwiftUI
import UIKit

/// The user's light/dark choice. `system` follows iOS. Stored in UserDefaults and applied to every window.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance.v1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: Copy.Settings.appearanceSystem
        case .light: Copy.Settings.appearanceLight
        case .dark: Copy.Settings.appearanceDark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    static var stored: AppearancePreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppearancePreference.init(rawValue:)) ?? .system
    }
}

/// Window-level glue: SwiftUI's `preferredColorScheme` does not reach sheets' chrome, the keyboard or the
/// privacy cover, so the style is set on every window of the scene.
@MainActor
enum AppearanceWindows {
    static func applyToAllWindows(_ preference: AppearancePreference = .stored) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) { apply(to: window, preference) }
    }

    static func apply(to window: UIWindow, _ preference: AppearancePreference = .stored) {
        window.overrideUserInterfaceStyle = preference.interfaceStyle
        // Only app-owned windows get the paper background; system windows (keyboard, text effects) stay clear
        // so they never paint over the app. Paper behind the views replaces the black seen at the keyboard's corners.
        if type(of: window) == UIWindow.self { window.backgroundColor = Palette.UI.paper }
    }
}
