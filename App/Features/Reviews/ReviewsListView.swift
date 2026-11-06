import ReytKit
import SwiftUI

/// Where a push from the reviews stack goes.
enum ReviewRoute: Hashable {
    case week(DateKey)
    case day(DateKey)
}

/// The Reviews tab: every eligible week, newest first, the latest one marked. A lazy `List`, so a journal
/// imported with years of history stays light.
struct ReviewsListView: View {
    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore

    @Environment(HealthCoordinator.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ReviewsListModel
    @State private var path: [ReviewRoute] = []
    @State private var today = AppClock.today()

    init(store: JournalStore, events: JournalEvents, attachments: AttachmentStore) {
        self.store = store
        self.events = events
        self.attachments = attachments
        _model = State(initialValue: ReviewsListModel(store: store, events: events))
        var initial: [ReviewRoute] = []
        #if DEBUG
            // Simulator-only: `-openReview YYYY-MM-DD` (a week's Sunday) opens that review as if it had been tapped.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-openReview"), args.indices.contains(i + 1), let key = DateKey(args[i + 1])
            {
                initial = [.week(key)]
            }
        #endif
        _path = State(initialValue: initial)
    }

    private struct RefreshKey: Equatable {
        var revision: Int
        var today: DateKey
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Palette.paper)
                .navigationTitle(Copy.Reviews.title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: ReviewRoute.self) { route in
                    switch route {
                    case .week(let key):
                        ReviewView(weekStart: key, store: store, events: events)
                    case .day(let key):
                        HistoryDayPage(key: key, store: store, events: events, attachments: attachments)
                    }
                }
        }
        .task(id: RefreshKey(revision: events.contentRevision, today: today)) {
            await model.refresh(today: today)
            await health.syncIfDue()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = AppClock.today() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { today = AppClock.today() } }
    }

    @ViewBuilder private var content: some View {
        if model.loadFailed {
            Button(Copy.Reviews.loadFailed) { Task { await model.refresh(today: today) } }
                .font(.footnote).foregroundStyle(Palette.accent).frame(minHeight: 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.isLoaded {
            Palette.paper
        } else if model.rows.isEmpty {
            Text(
                Copy.Reviews.emptyList(
                    opensOn: WeekCalendar.unlockKey(forWeekStart: WeekCalendar.reviewWeekStart(containing: today)))
            )
            .font(.body)
            .foregroundStyle(Palette.ink2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.rows) { row in
                NavigationLink(value: ReviewRoute.week(row.weekStart)) {
                    ReviewRowView(row: row, isLatest: row.weekStart == model.latestWeek, today: today)
                }
                .listRowBackground(Palette.paper)
                .listRowSeparatorTint(Palette.border)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ReviewRowView: View {
    let row: ReviewsListModel.Row
    let isLatest: Bool
    let today: DateKey

    private var week: String {
        Copy.Reviews.weekOf(
            DateRangeFormat.string(from: row.weekStart, to: row.weekStart.adding(days: 6), today: today))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLatest {
                Text(Copy.Reviews.thisWeeksReview).font(.footnote).foregroundStyle(Palette.accent)
            }
            Text(week)
                .font(isLatest ? .system(.title3, design: .serif) : .body)
                .foregroundStyle(Palette.ink)
            Text(Copy.Reviews.coverage(row.recordedDays)).font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, isLatest ? 8 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.Reviews.rowLabel(week: week, coverage: Copy.Reviews.coverage(row.recordedDays), isLatest: isLatest))
    }
}
