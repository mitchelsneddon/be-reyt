import ReytKit
import SwiftUI

/// Four tabs; Today is the root.
struct RootView: View {
    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore
    let backup: BackupSettingsModel
    let restore: RestoreCoordinator

    private enum Destination: String { case today, history, reviews, settings }

    /// Scene storage, so a relaunch after iOS ended the app in the background opens on the same tab.
    @SceneStorage("root.tab") private var selection = Destination.today

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: Destination.today) {
                TodayView(store: store, events: events, attachments: attachments)
            } label: {
                tabLabel(Copy.Tab.today, "tab.today", .today)
            }
            Tab(value: Destination.history) {
                HistoryView(store: store, events: events, attachments: attachments)
            } label: {
                tabLabel(Copy.Tab.history, "tab.history", .history)
            }
            Tab(value: Destination.reviews) {
                ReviewsListView(store: store, events: events, attachments: attachments)
            } label: {
                tabLabel(Copy.Tab.reviews, "tab.reviews", .reviews)
            }
            Tab(value: Destination.settings) {
                SettingsView(backup: backup, restore: restore)
            } label: {
                tabLabel(Copy.Tab.settings, "tab.settings", .settings)
            }
        }
        .tint(Palette.accent)
        #if DEBUG
            .task {
                // Simulator-only: `-openHistory ...` starts on the history tab.
                let args = CommandLine.arguments
                if args.contains("-openHistory") { selection = .history }
                if args.contains("-openSettings") { selection = .settings }
                if args.contains("-openReview") || args.contains("-openReviews") { selection = .reviews }
            }
        #endif
        .modifier(PassphraseQuestionAlerts(restore: restore))
        .environment(restore)
    }

    /// Outline when idle, filled when selected.
    private func tabLabel(_ title: String, _ image: String, _ destination: Destination) -> some View {
        Label(title, image: selection == destination ? "\(image).fill" : image)
    }
}

/// The one-time question after a restore: what to do about the backup passphrase on this phone.
private struct PassphraseQuestionAlerts: ViewModifier {
    let restore: RestoreCoordinator

    func body(content: Content) -> some View {
        content
            .alert(
                restore.passphraseQuestion == .keepOrSwitch
                    ? Copy.PassphraseQuestion.switchTitle : Copy.PassphraseQuestion.useTypedTitle,
                isPresented: Binding(
                    get: { restore.passphraseQuestion != nil },
                    set: {
                        if !$0, restore.passphraseQuestion != nil { restore.answerPassphraseQuestion(adopt: false) }
                    }
                )
            ) {
                if restore.passphraseQuestion == .keepOrSwitch {
                    Button(Copy.PassphraseQuestion.keep, role: .cancel) {
                        restore.answerPassphraseQuestion(adopt: false)
                    }
                    Button(Copy.PassphraseQuestion.switchTo) { restore.answerPassphraseQuestion(adopt: true) }
                } else {
                    Button(Copy.PassphraseQuestion.useTypedNo, role: .cancel) {
                        restore.answerPassphraseQuestion(adopt: false)
                    }
                    Button(Copy.PassphraseQuestion.useTypedYes) { restore.answerPassphraseQuestion(adopt: true) }
                }
            } message: {
                Text(
                    restore.passphraseQuestion == .keepOrSwitch
                        ? Copy.PassphraseQuestion.switchMessage : Copy.PassphraseQuestion.useTypedMessage)
            }
            .alert(
                Copy.PassphraseQuestion.saveFailed,
                isPresented: Binding(
                    get: { restore.passphraseSaveFailed },
                    set: { if !$0 { restore.dismissPassphraseSaveFailure() } })
            ) {
                Button(Copy.Restore.dismiss, role: .cancel) {}
            }
    }
}
