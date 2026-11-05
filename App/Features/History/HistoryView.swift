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
    @State private var searchPresented = false
    @Query(sort: \Tag.name) private var tags: [Tag]

    init(store: JournalStore, events: JournalEvents, attachments: AttachmentStore) {
        self.store = store
        self.events = events
        self.attachments = attachments
        let model = HistoryModel(store: store)
        var initialMode = Mode.calendar
        var presented = false
        #if DEBUG
            // Simulator-only: `-openHistory calendar|list`, `-historySearch <text>` for screenshots.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-openHistory"), args.indices.contains(i + 1) {
                initialMode = args[i + 1] == "list" ? .list : .calendar
            }
            if let i = args.firstIndex(of: "-historySearch"), args.indices.contains(i + 1) {
                model.searchText = args[i + 1]
                presented = true
            }
        #endif
        _model = State(initialValue: model)
        _mode = State(initialValue: initialMode)
        _searchPresented = State(initialValue: presented)
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
                if !model.isFiltering && !model.days.isEmpty {
                    Picker(Copy.History.modeLabel, selection: $mode) {
                        Text(Copy.History.calendar).tag(Mode.calendar)
                        Text(Copy.History.list).tag(Mode.list)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                if searchPresented || !model.tagIDs.isEmpty, !tags.isEmpty { tagFilter }
                content
            }
            .background(Color("paper"))
            .navigationTitle(Copy.Tab.history)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.searchText, isPresented: $searchPresented,
                prompt: Text(Copy.History.searchPrompt)
            )
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
        .task(id: RefreshKey(revision: events.contentRevision, text: model.searchText, tags: model.tagIDs)) {
            // Light debounce so typing does not fetch on every keystroke; a newer key cancels this one.
            if model.isFiltering { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
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
            Button(Copy.History.loadFailed) { Task { await model.refresh() } }
                .font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.isLoaded {
            Color("paper")
        } else if model.isFiltering {
            if model.results.isEmpty {
                message(Copy.History.noMatches)
            } else {
                HistoryList(days: model.results)
            }
        } else if model.days.isEmpty {
            message(Copy.History.emptyJournal)
        } else if mode == .list {
            HistoryList(days: model.days)
        } else {
            ScrollView {
                HistoryCalendar(
                    dotDays: model.dotDays, earliest: model.days.last?.dateKey ?? AppClock.today(),
                    today: AppClock.today(), openDay: path.last,
                    onSelect: open
                )
                .padding(.horizontal, 12)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Color("inkSecondary"))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
