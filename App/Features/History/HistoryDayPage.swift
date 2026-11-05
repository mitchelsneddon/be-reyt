import ReytKit
import SwiftUI

/// A day opened from history: the same `DayPageView`, built the way Today builds it. The arrows step between
/// days; next stops at today, so a future day can never be opened.
struct HistoryDayPage: View {
    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore

    @State private var today = AppClock.today()
    @State private var model: DayPageModel
    @State private var photos: PhotosModel

    init(key: DateKey, store: JournalStore, events: JournalEvents, attachments: AttachmentStore) {
        self.store = store
        self.events = events
        self.attachments = attachments
        _model = State(initialValue: DayPageModel(dateKey: key, store: store, events: events))
        _photos = State(initialValue: PhotosModel(dateKey: key, attachments: attachments, events: events))
    }

    var body: some View {
        DayPageView(model: model, photos: photos, today: today, onNavigate: show)
            .id(model.dateKey)
            .navigationBarTitleDisplayMode(.inline)
    }

    private func show(_ key: DateKey) {
        let current = AppClock.today()
        today = current
        guard key <= current else { return }
        model = DayPageModel(dateKey: key, store: store, events: events)
        photos = PhotosModel(dateKey: key, attachments: attachments, events: events)
    }
}
