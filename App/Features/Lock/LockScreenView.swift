import ReytKit
import SwiftUI

/// Shown over the journal while locked, in its own window above every sheet (`LockWindow`). Until an unlock
/// attempt has been cancelled or failed it is the plain cover, so launch goes cover, Face ID, journal with no
/// unlock button flashing up in between.
struct LockScreenView: View {
    let lock: AppLock

    var body: some View {
        if lock.offersUnlock {
            unlockPrompt
        } else {
            PrivacyCover()
        }
    }

    private var unlockPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                LockMark()
                    .padding(.vertical, 2)
                Text(Copy.Lock.appName)
                    .brFont(.largeTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.Lock.tagline)
                    .brFont(.bodyItalic)
                    .foregroundStyle(Palette.ink2)
            }
            Button {
                Task { await lock.authenticate() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "faceid")
                        .symbolSize(24)
                        .accessibilityHidden(true)
                    Text(Copy.Lock.unlock)
                        .brFont(.navTitle)
                }
                .foregroundStyle(Palette.onAccent)
                .padding(.leading, 22)
                .padding(.trailing, 28)
                .frame(minHeight: 48)
                .background(Capsule().fill(Palette.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 36)
            .accessibilityLabel(Copy.Lock.unlock)
            .accessibilityHint(Copy.Lock.unlockHint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 214)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        .ignoresSafeArea(edges: .top)
    }
}

/// Opaque cover for any non-active scene phase, so the app-switcher snapshot never shows content.
/// Shown in its own window (`PrivacyCoverWindow`), because a SwiftUI overlay sits below sheets and full-screen covers.
struct PrivacyCover: View {
    var body: some View {
        VStack(spacing: 22) {
            LockMark()
            Text(Copy.Lock.appName)
                .brFont(.largeTitle)
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
        .accessibilityHidden(true)
    }
}

/// Persistent, calm warning when there is no device passcode to lock with.
struct NoPasscodeBanner: View {
    var body: some View {
        NoteBanner(icon: "lock.trianglebadge.exclamationmark", text: Copy.Lock.noPasscode)
    }
}
