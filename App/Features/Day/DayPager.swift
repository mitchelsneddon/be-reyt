import ReytKit
import SwiftUI
import UIKit

/// Owns the page models for the days near the open one. Models are created on demand and only the open day
/// plus two either side are kept; a model is flushed before it is dropped so no draft is lost.
@Observable @MainActor
final class DayPageCache {
    static let keepRadius = 2

    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let attachments: AttachmentStore
    @ObservationIgnored private var models: [DateKey: DayPageModel] = [:]
    @ObservationIgnored private var photoModels: [DateKey: PhotosModel] = [:]

    init(store: JournalStore, events: JournalEvents, attachments: AttachmentStore) {
        self.store = store
        self.events = events
        self.attachments = attachments
    }

    func model(for key: DateKey) -> DayPageModel {
        if let existing = models[key] { return existing }
        let model = DayPageModel(dateKey: key, store: store, events: events)
        models[key] = model
        return model
    }

    func photos(for key: DateKey) -> PhotosModel {
        if let existing = photoModels[key] { return existing }
        let photos = PhotosModel(dateKey: key, attachments: attachments, events: events)
        photoModels[key] = photos
        return photos
    }

    /// The model for `key` only if one exists (never creates).
    func existingModel(for key: DateKey) -> DayPageModel? { models[key] }

    /// Drops everything farther than `keepRadius` days from `key`, flushing each model first.
    func prune(around key: DateKey) {
        let keep = (-Self.keepRadius...Self.keepRadius).map { key.adding(days: $0) }
        for (day, model) in models where !keep.contains(day) {
            model.flush()
            models[day] = nil
        }
        for day in photoModels.keys where !keep.contains(day) { photoModels[day] = nil }
    }
}

/// Days laid side by side, from ten years back to `today`, paged with the finger. One toolbar for the open day.
struct DayPager: View {
    let cache: DayPageCache
    @Binding var current: DateKey
    /// The latest civil day; there are no future pages.
    let today: DateKey

    private static let spanDays = 3650

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lowerBound: DateKey { min(today.adding(days: -Self.spanDays), current) }

    private var position: Binding<DateKey?> {
        Binding(get: { current }, set: { if let key = $0, key != current { current = key } })
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(lowerBound.epochDay...today.epochDay, id: \.self) { epoch in
                    let key = DateKey(epochDay: epoch)
                    DayPageView(
                        model: cache.model(for: key), photos: cache.photos(for: key), today: today,
                        onOpenDay: go
                    )
                    .id(key)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: position)
        .scrollIndicators(.hidden)
        .onChange(of: current) { old, new in
            cache.existingModel(for: old)?.flush()
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            cache.prune(around: new)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    step(-1)
                } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Copy.Day.previousDay)
                Button {
                    step(1)
                } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(current >= today)
                .accessibilityLabel(Copy.Day.nextDay)
            }
            ToolbarItem(placement: .topBarTrailing) {
                let model = cache.model(for: current)
                SavedIndicator(state: model.saveState, retry: model.retry)
            }
        }
    }

    private func step(_ days: Int) { go(current.adding(days: days)) }

    /// Moves the pager to `key` with animation, ignoring days outside the paged range.
    private func go(_ key: DateKey) {
        guard key <= today, key >= lowerBound else { return }
        cache.model(for: current).flush()
        if reduceMotion {
            current = key
        } else {
            withAnimation { current = key }
        }
    }
}
