import SwiftUI

/// The first-run cover: one of three skippable steps at a time, cross-fading, no back button.
struct OnboardingView: View {
    let backup: BackupSettingsModel
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        ZStack {
            switch model.step {
            case .reminder: ReminderStep().transition(.opacity)
            case .workouts: WorkoutsStep().transition(.opacity)
            case .backups: BackupsStep(backup: backup).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.step)
        .background(Palette.paper.ignoresSafeArea())
        .tint(Palette.accent)
    }
}

// MARK: Steps

private struct ReminderStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ReminderScheduler.self) private var reminders
    @State private var draftOn = true
    @State private var hour = 21
    @State private var busy = false

    var body: some View {
        OnboardingScaffold(
            step: 1, title: Copy.Onboarding.reminderTitle,
            hero: { OnboardingHero(systemName: "bell") },
            content: {
                VStack(spacing: 0) {
                    Toggle(isOn: $draftOn.animation()) {
                        SettingsRowLabel(title: Copy.Reminder.toggle, icon: "bell")
                    }
                    .padding(.horizontal, 16)
                    if draftOn {
                        Rectangle().fill(Palette.border).frame(height: 1)
                        HStack(spacing: 0) {
                            SettingsRowLabel(title: Copy.Reminder.time, icon: "clock")
                            Picker(Copy.Reminder.time, selection: $hour) {
                                ForEach(0..<24, id: \.self) { Text(Copy.Reminder.hourLabel($0)).tag($0) }
                            }
                            .labelsHidden()
                            .brFont(.row)
                            .tint(Palette.ink2)
                            .frame(minHeight: 44)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .brFont(.row)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1)
                )
            },
            primary: Copy.Onboarding.continueButton, primaryEnabled: !busy,
            primaryAction: {
                busy = true
                // Turning it on asks for notification permission here, in context. A denial continues silently.
                await reminders.setEnabled(draftOn)
                if draftOn { await reminders.setHour(hour) }
                busy = false
                model.advance()
            },
            secondary: Copy.Onboarding.notNow, secondaryEnabled: !busy,
            secondaryAction: {
                busy = true
                await reminders.setEnabled(false)
                busy = false
                model.advance()
            }
        )
        .task {
            await reminders.refresh()
            draftOn = reminders.settings.enabled
            hour = reminders.settings.hour
        }
    }
}

private struct WorkoutsStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(HealthCoordinator.self) private var health
    @State private var busy = false

    var body: some View {
        OnboardingScaffold(
            step: 2, title: Copy.Onboarding.workoutsTitle,
            hero: { OnboardingHero(systemName: "waveform.path.ecg") },
            content: { WorkoutPreviewCard() },
            primary: health.access == .asked ? Copy.Onboarding.continueButton : Copy.Onboarding.allowWorkouts,
            primaryEnabled: !busy,
            primaryAction: {
                if health.access != .asked {
                    busy = true
                    await health.requestAccess()
                    busy = false
                }
                model.advance()
            },
            secondary: Copy.Onboarding.notNow, secondaryEnabled: !busy,
            secondaryAction: { model.advance() }
        )
        .task {
            if health.access == .unknown { await health.refreshAccess() }
            if health.access == .unavailable { model.advance() }
        }
    }
}

private struct BackupsStep: View {
    let backup: BackupSettingsModel
    @Environment(OnboardingModel.self) private var model
    @Environment(BackupManager.self) private var manager
    @State private var showPicker = false
    @State private var showPassphrase = false

    private var folderSet: Bool { manager.hasDestination }
    private var passphraseSet: Bool { backup.hasPassphrase }
    private var ready: Bool { folderSet && passphraseSet }

    var body: some View {
        OnboardingScaffold(
            step: 3, title: Copy.Onboarding.backupsTitle,
            hero: { FolderLock() },
            content: {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        row(
                            title: folderSet ? Copy.Onboarding.folderRow : Copy.Onboarding.chooseFolder,
                            icon: "folder",
                            value: folderSet ? (manager.folderName ?? "") : Copy.Onboarding.notSetUp,
                            done: folderSet, hint: Copy.Onboarding.chooseFolderHint
                        ) { showPicker = true }
                        Rectangle().fill(Palette.border).frame(height: 1)
                        row(
                            title: Copy.Onboarding.passphraseRow, icon: "key",
                            value: passphraseSet ? Copy.Onboarding.isSet : Copy.Onboarding.notSetYet,
                            done: passphraseSet, hint: Copy.Onboarding.passphraseHint
                        ) { showPassphrase = true }
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )
                    if !ready {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "iphone").accessibilityHidden(true)
                            Text(Copy.Onboarding.phoneOnly)
                        }
                        .brFont(.rowWrapping)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 4)
                    }
                }
            },
            primary: Copy.Onboarding.startWriting, primaryEnabled: ready,
            primaryAction: { model.finish() },
            secondary: Copy.Onboarding.later, secondaryHidden: ready,
            secondaryAction: { model.finish() }
        )
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await manager.chooseFolder(url) } }
        }
        .sheet(isPresented: $showPassphrase) {
            PassphraseView(backup: backup, isChange: passphraseSet)
        }
        .task {
            backup.refresh()
            await manager.refreshDestination()
            #if DEBUG
                // Simulator-only: the debug passphrase is applied by a launch task, so look again briefly.
                for _ in 0..<6 {
                    try? await Task.sleep(for: .milliseconds(500))
                    backup.refresh()
                    await manager.refreshDestination()
                }
            #endif
        }
    }

    private func row(
        title: String, icon: String, value: String, done: Bool, hint: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                SettingsRowLabel(title: title, icon: icon, value: value, chevron: !done)
                if done {
                    Image(systemName: "checkmark")
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.ok)
                        .padding(.leading, 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}

// MARK: Shared pieces

/// The shared layout: top row, hero, title, control area, and the pinned buttons.
private struct OnboardingScaffold<Hero: View, Content: View>: View {
    let step: Int
    let title: String
    @ViewBuilder let hero: Hero
    @ViewBuilder let content: Content
    let primary: String
    var primaryEnabled = true
    let primaryAction: () async -> Void
    var secondary: String?
    var secondaryEnabled = true
    var secondaryHidden = false
    var secondaryAction: () async -> Void = {}

    init(
        step: Int, title: String, @ViewBuilder hero: () -> Hero, @ViewBuilder content: () -> Content,
        primary: String, primaryEnabled: Bool = true, primaryAction: @escaping () async -> Void,
        secondary: String, secondaryEnabled: Bool = true, secondaryHidden: Bool = false,
        secondaryAction: @escaping () async -> Void
    ) {
        self.step = step
        self.title = title
        self.hero = hero()
        self.content = content()
        self.primary = primary
        self.primaryEnabled = primaryEnabled
        self.primaryAction = primaryAction
        self.secondary = secondary
        self.secondaryEnabled = secondaryEnabled
        self.secondaryHidden = secondaryHidden
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopRow(step: step)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero.padding(.top, 56)
                    Text(title)
                        .brFont(.onboardingTitle)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                        .accessibilityAddTraits(.isHeader)
                    content.padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Button(primary) { Task { await primaryAction() } }
                    .buttonStyle(.brPrimary)
                    .disabled(!primaryEnabled)
                if let secondary {
                    Button(secondary) { Task { await secondaryAction() } }
                        .buttonStyle(.brSecondary)
                        .disabled(!secondaryEnabled)
                        .opacity(secondaryHidden ? 0 : 1)
                        .accessibilityHidden(secondaryHidden)
                        .allowsHitTesting(!secondaryHidden)
                }
            }
            .padding(.horizontal, 24)
            .background(Palette.paper)
        }
    }
}

private struct OnboardingTopRow: View {
    let step: Int

    var body: some View {
        HStack {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(Copy.Onboarding.wordmarkStart)
                Circle()
                    .fill(Palette.wordmarkDot)
                    .frame(width: 5, height: 5)
                    .padding(.leading, 2).padding(.trailing, 5)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] + 1 }
                Text(Copy.Onboarding.wordmarkEnd)
            }
            .brFont(.wordmark)
            .foregroundStyle(Palette.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.Onboarding.wordmark)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    if index == step {
                        Capsule().fill(Palette.accent).frame(width: 18, height: 7)
                    } else {
                        Circle().fill(Palette.ink3).frame(width: 7, height: 7)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.Onboarding.stepLabel(step))
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 24)
    }
}

/// The 88pt accentSoft disc with a 40pt accent symbol.
private struct OnboardingHero: View {
    let systemName: String
    @ScaledMetric(relativeTo: .largeTitle) private var disc: CGFloat = 88

    var body: some View {
        let side = min(disc, 132)
        ZStack {
            Circle().fill(Palette.accentSoft)
            Image(systemName: systemName)
                .resizable().scaledToFit()
                .fontWeight(.light)
                .frame(width: side * 40 / 88, height: side * 40 / 88)
                .foregroundStyle(Palette.accent)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// What a workout looks like on Today, as a quiet example. Decoration only.
private struct WorkoutPreviewCard: View {
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = 22

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: WorkoutCard.symbol(for: .yoga))
                .resizable().scaledToFit()
                .frame(width: min(glyphSide, 34), height: min(glyphSide, 34))
                .foregroundStyle(Palette.accent)
                .frame(width: min(tileSide, 64), height: min(tileSide, 64))
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.Onboarding.previewName).brFont(.cardTitle).foregroundStyle(Palette.ink)
                Text(Copy.Onboarding.previewDuration).brFont(.label).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Copy.Onboarding.previewTime).brFont(.captionItalic).foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 2)
        .cardSurface(padding: 14)
        .opacity(0.9)
        .accessibilityHidden(true)
    }
}
