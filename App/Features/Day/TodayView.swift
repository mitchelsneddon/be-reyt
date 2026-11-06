import ReytKit
import SwiftUI

/// The Today tab: the day page for today, with a previous/next arrow, and the expiry banner.
/// Rolls to a new day at midnight only when the open page is idle; otherwise the open day stays.
struct TodayView: View {
    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore
    var provisioning = ProvisioningInfo.load()
    /// Injected so the banner rule can be exercised with any date.
    var now: () -> Date = { .now }

    @Environment(\.scenePhase) private var scenePhase
    @State private var today: DateKey
    @State private var current: DateKey
    @State private var cache: DayPageCache
    /// True while the open page is the live "today" (so a roll may move it), false after the user pages back.
    @State private var followsToday = true

    init(
        store: JournalStore, events: JournalEvents, attachments: AttachmentStore,
        provisioning: ProvisioningInfo = .load()
    ) {
        self.store = store
        self.events = events
        self.attachments = attachments
        self.provisioning = provisioning
        let key = Self.currentDay()
        _today = State(initialValue: key)
        _current = State(initialValue: key)
        _cache = State(initialValue: DayPageCache(store: store, events: events, attachments: attachments))
    }

    var body: some View {
        NavigationStack {
            DayPager(cache: cache, current: $current, today: today)
                .completionNotes()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let days = provisioning.daysLeftIfExpiring(now: now()) {
                        ExpiryBanner(daysLeft: days)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollIfIdle() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { rollIfIdle() } }
        .onChange(of: cache.model(for: current).isIdle) { _, _ in rollIfIdle() }
        .onChange(of: current) { _, key in followsToday = key == today }
    }

    private static func currentDay() -> DateKey { AppClock.today() }

    private func rollIfIdle() {
        let latest = Self.currentDay()
        today = latest
        if followsToday, current != latest, cache.model(for: current).isIdle { current = latest }
    }
}
