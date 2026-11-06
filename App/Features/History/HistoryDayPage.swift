import ReytKit
import SwiftUI

/// A day opened from history: the same pager Today uses, starting at the opened day. Swipe or use the arrows
/// to step between days; the last page is today, so a future day can never be opened.
struct HistoryDayPage: View {
    @State private var today = AppClock.today()
    @State private var current: DateKey
    @State private var cache: DayPageCache

    init(key: DateKey, store: JournalStore, events: JournalEvents, attachments: AttachmentStore) {
        _current = State(initialValue: key)
        _cache = State(initialValue: DayPageCache(store: store, events: events, attachments: attachments))
    }

    var body: some View {
        DayPager(cache: cache, current: $current, today: today)
            .navigationBarTitleDisplayMode(.inline)
    }
}
