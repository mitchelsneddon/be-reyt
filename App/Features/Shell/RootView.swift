import ReytKit
import SwiftUI

/// Four tabs; Today is the root.
struct RootView: View {
    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore
    let backup: BackupSettingsModel
    let restore: RestoreCoordinator

    private enum Destination: Hashable { case today, history, reviews, settings }

    @State private var selection: Destination = Self.initialSelection

    private static var initialSelection: Destination {
        #if DEBUG
            // Simulator-only: `-openHistory ...` starts on the history tab.
            if CommandLine.arguments.contains("-openHistory") { return .history }
            if CommandLine.arguments.contains("-openSettings") { return .settings }
            if CommandLine.arguments.contains("-openReview") || CommandLine.arguments.contains("-openReviews") {
                return .reviews
            }
        #endif
        return .today
    }

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
                SettingsView(backup: backup, restore: restore, tags: TagsModel(store: store, events: events))
            } label: {
                tabLabel(Copy.Tab.settings, "tab.settings", .settings)
            }
        }
        .tint(Palette.accent)
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
