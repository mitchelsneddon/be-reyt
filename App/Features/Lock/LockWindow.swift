import SwiftUI
import UIKit

/// Puts `LockScreenView` in its own window above everything the journal can present (sheets, full-screen covers,
/// alerts), so the journal can stay alive underneath while locked and come back exactly where it was. Sits below
/// `PrivacyCoverWindow`, which still covers the app-switcher snapshot.
@MainActor
final class LockWindow {
    static let shared = LockWindow()

    private var window: UIWindow?

    func setVisible(_ visible: Bool, lock: AppLock) {
        if visible {
            guard let window = window ?? makeWindow(lock: lock) else { return }
            self.window = window
            // Key, so VoiceOver and the keyboard stay on the lock screen rather than the journal behind it.
            window.makeKeyAndVisible()
        } else if let window, !window.isHidden {
            window.isHidden = true
            window.windowScene?.windows.first { $0.windowLevel == .normal && !$0.isHidden }?.makeKey()
        }
    }

    private func makeWindow(lock: AppLock) -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else {
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 50
        let controller = UIHostingController(rootView: LockScreenView(lock: lock))
        controller.view.backgroundColor = Palette.UI.paper
        window.rootViewController = controller
        AppearanceWindows.apply(to: window)
        return window
    }
}
