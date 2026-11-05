import ReytKit
import SwiftUI

/// Four tabs; Today is the root. History, reviews and settings are placeholders until their sections land.
struct RootView: View {
    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore

    var body: some View {
        TabView {
            Tab(Copy.Tab.today, systemImage: "sun.horizon") {
                TodayView(store: store, events: events, attachments: attachments)
            }
            Tab(Copy.Tab.history, systemImage: "calendar") {
                PlaceholderScreen(title: Copy.Tab.history, message: Copy.Placeholder.historyBody)
            }
            Tab(Copy.Tab.reviews, systemImage: "text.book.closed") {
                PlaceholderScreen(title: Copy.Tab.reviews, message: Copy.Placeholder.reviewsBody)
            }
            Tab(Copy.Tab.settings, systemImage: "gearshape") {
                PlaceholderScreen(title: Copy.Tab.settings, message: Copy.Placeholder.settingsBody)
            }
        }
        .tint(Color("accent"))
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
