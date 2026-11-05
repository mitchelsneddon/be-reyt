import ReytKit
import SwiftUI

/// The Today tab: the day page for today, with a previous/next arrow, and the expiry banner.
/// Rolls to a new day at midnight only when the open page is idle; otherwise the open day stays.
struct TodayView: View {
    let store: JournalStore
    let events: JournalEvents
    var provisioning = ProvisioningInfo.load()
    /// Injected so the banner rule can be exercised with any date.
    var now: () -> Date = { .now }

    @Environment(\.scenePhase) private var scenePhase
    @State private var today: DateKey
    @State private var model: DayPageModel
    /// True while the open page is the live "today" (so a roll may move it), false after the user steps back.
    @State private var followsToday = true

    init(store: JournalStore, events: JournalEvents, provisioning: ProvisioningInfo = .load()) {
        self.store = store
        self.events = events
        self.provisioning = provisioning
        let key = Self.currentDay()
        _today = State(initialValue: key)
        _model = State(initialValue: DayPageModel(dateKey: key, store: store, events: events))
    }

    var body: some View {
        NavigationStack {
            DayPageView(model: model, today: today, onNavigate: show)
                .id(model.dateKey)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let days = provisioning.daysLeftIfExpiring(now: now()) {
                        ExpiryBanner(daysLeft: days)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollIfIdle() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { rollIfIdle() } }
        .onChange(of: model.isIdle) { _, _ in rollIfIdle() }
    }

    private static func currentDay() -> DateKey { DateKey(date: .now, calendar: .current) }

    private func show(_ key: DateKey) {
        guard key <= today else { return }
        followsToday = key == today
        model = DayPageModel(dateKey: key, store: store, events: events)
    }

    private func rollIfIdle() {
        let current = Self.currentDay()
        today = current
        if followsToday, model.dateKey != current, model.isIdle { show(current) }
    }
}
