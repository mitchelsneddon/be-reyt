import SwiftUI
import UIKit

/// Puts `PrivacyCover` in its own window above everything the app can present (sheets, full-screen covers, alerts),
/// so the app-switcher snapshot never shows journal content. Shown whenever the scene is not active.
@MainActor
final class PrivacyCoverWindow {
    static let shared = PrivacyCoverWindow()

    private var window: UIWindow?

    func setVisible(_ visible: Bool) {
        if visible {
            guard let window = window ?? makeWindow() else { return }
            self.window = window
            window.isHidden = false
        } else {
            window?.isHidden = true
        }
    }

    private func makeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else {
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 100
        let controller = UIHostingController(rootView: PrivacyCover())
        controller.view.backgroundColor = Palette.UI.paper
        window.rootViewController = controller
        AppearanceWindows.apply(to: window)
        return window
    }
}
