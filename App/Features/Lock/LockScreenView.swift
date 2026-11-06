import ReytKit
import SwiftUI

/// Shown instead of the journal while locked. The journal UI is not in the hierarchy at all, so nothing can be
/// read by VoiceOver or snapshotted behind it.
struct LockScreenView: View {
    let lock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            Text(Copy.Lock.appName)
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(Copy.Lock.tagline)
                .font(.body)
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
            Button {
                Task { await lock.authenticate() }
            } label: {
                Text(Copy.Lock.unlock)
                    .font(.headline)
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Palette.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .accessibilityLabel(Copy.Lock.unlock)
            .accessibilityHint(Copy.Lock.unlockHint)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { lock.authenticateOnceIfNeeded() }
        }
    }
}

/// Opaque cover for any non-active scene phase, so the app-switcher snapshot never shows content.
/// Shown in its own window (`PrivacyCoverWindow`), because a SwiftUI overlay sits below sheets and full-screen covers.
struct PrivacyCover: View {
    var body: some View {
        Text(Copy.Lock.appName)
            .font(.system(.largeTitle, design: .serif))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.paper)
            .accessibilityHidden(true)
    }
}

/// Persistent, calm warning when there is no device passcode to lock with.
struct NoPasscodeBanner: View {
    var body: some View {
        Text(Copy.Lock.noPasscode)
            .font(.footnote)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Palette.card)
    }
}
