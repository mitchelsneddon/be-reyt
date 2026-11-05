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
            if CommandLine.arguments.contains("-openReview") { return .reviews }
        #endif
        return .today
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(Copy.Tab.today, systemImage: "sun.horizon", value: Destination.today) {
                TodayView(store: store, events: events, attachments: attachments)
            }
            Tab(Copy.Tab.history, systemImage: "calendar", value: Destination.history) {
                HistoryView(store: store, events: events, attachments: attachments)
            }
            Tab(Copy.Tab.reviews, systemImage: "text.book.closed", value: Destination.reviews) {
                ReviewsListView(store: store, events: events, attachments: attachments)
            }
            Tab(Copy.Tab.settings, systemImage: "gearshape", value: Destination.settings) {
                SettingsView(backup: backup, restore: restore)
            }
        }
        .tint(Color("accent"))
        .safeAreaInset(edge: .top, spacing: 0) {
            if let note = restore.completionNote {
                RestoreNoteBanner(text: note, dismiss: restore.dismissCompletionNote)
            }
        }
    }
}

/// One calm line after a restore (or undo) rebuilt the app.
private struct RestoreNoteBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.footnote).foregroundStyle(Color("ink"))
            Spacer()
            Button(Copy.Restore.dismiss, action: dismiss).font(.footnote).frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .background(Color("paper"))
        .accessibilityElement(children: .contain)
    }
}
