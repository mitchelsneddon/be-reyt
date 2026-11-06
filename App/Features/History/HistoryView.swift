import ReytKit
import SwiftData
import SwiftUI

/// The History tab: a calendar or a list of days with content, plus local search by text and tag.
struct HistoryView: View {
    private enum Mode: Hashable { case calendar, list }

    let store: JournalStore
    let events: JournalEvents
    let attachments: AttachmentStore

    @State private var model: HistoryModel
    @State private var mode: Mode = .calendar
    @State private var path: [DateKey] = []
    @Query(sort: \Tag.name) private var tags: [Tag]

    init(store: JournalStore, events: JournalEvents, attachments: AttachmentStore) {
        self.store = store
        self.events = events
        self.attachments = attachments
        let model = HistoryModel(store: store)
        var initialMode = Mode.calendar
        #if DEBUG
            // Simulator-only: `-openHistory calendar|list`, `-historySearch <text>` for screenshots.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-openHistory"), args.indices.contains(i + 1) {
                initialMode = args[i + 1] == "list" ? .list : .calendar
            }
            if let i = args.firstIndex(of: "-historySearch"), args.indices.contains(i + 1) {
                model.searchText = args[i + 1]
            }
        #endif
        _model = State(initialValue: model)
        _mode = State(initialValue: initialMode)
        _path = State(initialValue: [])
    }

    private struct RefreshKey: Equatable {
        var revision: Int
        var text: String
        var tags: Set<UUID>
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                if !tags.isEmpty { tagFilter }
                content
            }
            .background(Palette.paper)
            .completionNotes()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DateKey.self) { key in
                HistoryDayPage(key: key, store: store, events: events, attachments: attachments)
            }
        }
        #if DEBUG
            .task {
                // Simulator-only: `-openHistoryDay YYYY-MM-DD` opens that day as if it had been tapped.
                let args = CommandLine.arguments
                guard let i = args.firstIndex(of: "-openHistoryDay"), args.indices.contains(i + 1),
                    let key = DateKey(args[i + 1])
                else { return }
                open(key)
            }
        #endif
        .onChange(of: tags.map(\.id)) { _, ids in model.pruneTags(existing: Set(ids)) }
        .task(id: RefreshKey(revision: events.contentRevision, text: model.searchText, tags: model.tagIDs)) {
            // Light debounce so typing does not fetch on every keystroke; a newer key cancels this one.
            if model.isFiltering { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
    }

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            Text(Copy.Tab.history)
                .brFont(.screenTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
                .padding(.top, 8)
            searchField
            Picker(Copy.History.modeLabel, selection: $mode) {
                Text(Copy.History.list).tag(Mode.list)
                Text(Copy.History.calendar).tag(Mode.calendar)
            }
            .pickerStyle(.segmented)
            .tint(Palette.accent)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").symbolSize(18, maxPoints: 40).accessibilityHidden(true)
                .foregroundStyle(Palette.ink2)
            TextField(
                "", text: $model.searchText, prompt: Text(Copy.History.searchPrompt).foregroundStyle(Palette.ink2)
            )
            .brFont(.row)
            .foregroundStyle(Palette.ink)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .accessibilityLabel(Copy.History.searchPrompt)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.ink3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Copy.History.clearSearch)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, model.searchText.isEmpty ? 14 : 0)
        .frame(minHeight: 44)
        .background(Palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The one way a day gets pushed: calendar taps call this, and so does the DEBUG `-openHistoryDay` launch arg.
    /// Days after today are refused, the same rule the calendar applies to selection.
    private func open(_ key: DateKey) {
        guard key <= AppClock.today() else { return }
        path.append(key)
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ChipGroup(
                items: tags.map { ChipItem(id: $0.id, label: $0.name) },
                selection: Binding(get: { model.tagIDs }, set: { model.tagIDs = $0 })
            )
            .padding(.horizontal, 20)
        }
        .accessibilityLabel(Copy.History.tagFilterLabel)
        .frame(minHeight: 44)
    }

    @ViewBuilder private var content: some View {
        if model.loadFailed {
            Button {
                Task { await model.refresh() }
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.clockwise").symbolSize(24, maxPoints: 40).accessibilityHidden(true)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 56, height: 56)
                        .background(Palette.accentSoft, in: Circle())
                    Text(Copy.History.loadFailed)
                        .brFont(.rowWrapping)
                        .foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.center)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if !model.isLoaded {
            Palette.paper
        } else if model.isFiltering {
            if model.results.isEmpty {
                message(Copy.History.noMatches, symbol: "magnifyingglass")
            } else {
                HistoryList(days: model.results)
            }
        } else if model.days.isEmpty {
            message(Copy.History.emptyJournal, symbol: "calendar")
        } else if mode == .list {
            HistoryList(days: model.days)
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    HistoryCalendar(
                        dayScores: model.dayScores, earliest: model.days.last?.dateKey ?? AppClock.today(),
                        today: AppClock.today(), openDay: path.last,
                        onSelect: open
                    )
                    ScoreLegend()
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: symbol).symbolSize(34, maxPoints: 40).accessibilityHidden(true)
                .foregroundStyle(Palette.accent)
                .frame(width: 76, height: 76)
                .background(Palette.accentSoft, in: Circle())
            Text(text)
                .brFont(.stat)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The five faces with their names, under the calendar: what each dot colour means.
private struct ScoreLegend: View {
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let count = typeSize.isAccessibilitySize ? 2 : 5
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: count),
            spacing: 12
        ) {
            ForEach(DayScore.allCases, id: \.self) { score in
                VStack(spacing: 6) {
                    Circle().fill(Palette.score(score))
                        .frame(width: circle, height: circle)
                        .overlay {
                            FaceGlyph(score: score, size: circle * 19 / 28, strokeUnits: 2.8)
                                .foregroundStyle(Palette.faceInk)
                        }
                    Text(score.label)
                        .brFont(.label)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.History.scoreKey)
    }
}
