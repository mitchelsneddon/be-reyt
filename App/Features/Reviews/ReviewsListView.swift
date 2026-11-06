import ReytKit
import SwiftUI

/// Where a push from the reviews stack goes.
enum ReviewRoute: Hashable {
    case week(DateKey)
    case day(DateKey)
}

/// The Reviews tab: every eligible week, newest first, the latest one as a lead card. Lazy stacks, so a journal
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
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.Reviews.title)
                    .brFont(.largeTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(EdgeInsets(top: 18, leading: 28, bottom: 22, trailing: 24))
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.paper)
            .completionNotes()
            .toolbar(.hidden, for: .navigationBar)
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
            Button {
                Task { await model.refresh(today: today) }
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 56, height: 56)
                        .background(Palette.accentSoft, in: Circle())
                    Text(Copy.Reviews.loadFailed)
                        .brFont(.rowWrapping)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.center)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.Reviews.loadFailed)
            .padding(.horizontal, 40)
            .padding(.top, 120)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        } else if !model.isLoaded {
            Spacer(minLength: 0)
        } else if model.rows.isEmpty {
            VStack(spacing: 22) {
                Image(systemName: "star")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 76, height: 76)
                    .background(Palette.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(
                    Copy.Reviews.emptyList(
                        opensOn: WeekCalendar.unlockKey(forWeekStart: WeekCalendar.reviewWeekStart(containing: today)))
                )
                .brFont(.stat)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .padding(.top, 90)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let lead = model.rows.first {
                        NavigationLink(value: ReviewRoute.week(lead.weekStart)) {
                            LeadReviewCard(row: lead)
                        }
                        .buttonStyle(.plain)
                    }
                    let others = Array(model.rows.dropFirst())
                    if !others.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(others) { row in
                                if row.id != others.first?.id { Divider().overlay(Palette.border) }
                                NavigationLink(value: ReviewRoute.week(row.weekStart)) {
                                    WeekRow(row: row)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

/// Seven small circles for a week: filled in the day's score colour, dashed where there is no score.
private struct WeekDots: View {
    let scores: [DayScore?]
    let size: CGFloat
    let gap: CGFloat
    let missing: Color

    var body: some View {
        HStack(spacing: gap) {
            ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                if let score {
                    Circle().fill(Palette.score(score)).frame(width: size, height: size)
                } else {
                    Circle()
                        .strokeBorder(missing, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                        .frame(width: size, height: size)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .accessibilityHidden(true)
    }
}

private struct LeadReviewCard: View {
    let row: ReviewsListModel.Row

    private var week: String { Copy.Reviews.weekOfStart(row.weekStart) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Copy.Reviews.thisWeeksReview).brFont(.labelBold).opacity(0.82)
                Spacer(minLength: 8)
                Chevron().opacity(0.7)
            }
            Text(week).brFont(.leadCard).padding(.top, 6)
            Text(Copy.Reviews.coverage(row.recordedDays)).brFont(.banner).opacity(0.82).padding(.top, 2)
            WeekDots(scores: row.scores, size: 22, gap: 8, missing: Palette.onAccent.opacity(0.47))
                .padding(.top, 16)
        }
        .foregroundStyle(Palette.onAccent)
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.Reviews.rowLabel(week: week, coverage: Copy.Reviews.coverage(row.recordedDays), isLatest: true))
    }
}

private struct WeekRow: View {
    let row: ReviewsListModel.Row

    private var week: String { Copy.Reviews.weekOfStart(row.weekStart) }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(week).brFont(.weekRow).foregroundStyle(row.recordedDays == 0 ? Palette.ink2 : Palette.ink)
                Text(Copy.Reviews.coverage(row.recordedDays)).brFont(.label).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            WeekDots(scores: row.scores, size: 9, gap: 4, missing: Palette.ink3)
            Chevron().foregroundStyle(Palette.ink3)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.Reviews.rowLabel(week: week, coverage: Copy.Reviews.coverage(row.recordedDays), isLatest: false))
    }
}
