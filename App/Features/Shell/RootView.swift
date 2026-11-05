import ReytKit
import SwiftUI

/// Four tabs; Today is the root. Reviews and settings are placeholders until their sections land.
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
                PlaceholderScreen(title: Copy.Tab.reviews, message: Copy.Placeholder.reviewsBody)
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

struct PlaceholderScreen: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(Color("ink"))
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(.footnote).foregroundStyle(Color("inkSecondary"))
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color("paper"))
            .navigationBarTitleDisplayMode(.inline)
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
