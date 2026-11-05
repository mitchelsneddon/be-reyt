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
                .foregroundStyle(Color("ink"))
                .accessibilityAddTraits(.isHeader)
            Text(Copy.Lock.tagline)
                .font(.body)
                .foregroundStyle(Color("inkSecondary"))
                .multilineTextAlignment(.center)
            Button {
                Task { await lock.authenticate() }
            } label: {
                Text(Copy.Lock.unlock)
                    .font(.headline)
                    .foregroundStyle(Color("paper"))
                    .padding(.horizontal, 28)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color("accent")))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .accessibilityLabel(Copy.Lock.unlock)
            .accessibilityHint(Copy.Lock.unlockHint)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("paper"))
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { lock.authenticateOnceIfNeeded() }
        }
    }
}

/// Opaque cover for any non-active scene phase, so the app-switcher snapshot never shows content.
struct PrivacyCover: View {
    var body: some View {
        Text(Copy.Lock.appName)
            .font(.system(.largeTitle, design: .serif))
            .foregroundStyle(Color("ink"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("paper"))
            .accessibilityHidden(true)
    }
}

/// Persistent, calm warning when there is no device passcode to lock with.
struct NoPasscodeBanner: View {
    var body: some View {
        Text(Copy.Lock.noPasscode)
            .font(.footnote)
            .foregroundStyle(Color("ink"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color("card"))
    }
}
