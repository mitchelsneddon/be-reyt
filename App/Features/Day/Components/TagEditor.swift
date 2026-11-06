import ReytKit
import SwiftData
import SwiftUI

/// Tags for one day: the day's own tags (selected), up to six recent suggestions, and a field to add one.
/// Typing narrows the suggestions by case-insensitive prefix before a new tag is created.
/// Reads with `@Query` (A2 allows reads); every write goes through `DayPageModel` to `JournalStore`.
struct TagEditor: View {
    private static let suggestionLimit = 6

    @Environment(DayPageModel.self) private var model
    @Query(sort: \Tag.name) private var tags: [Tag]
    // shortcut: loads every entry to find each tag's last use, fine for a personal journal (thousands of rows); precompute past ~10k.
    @Query private var entries: [DailyEntry]
    @State private var newName = ""
    @State private var addFailed = false
    @State private var showManage = false

    private var dayTags: [Tag] { tags.filter { model.tagIDs.contains($0.id) } }

    /// Other tags, most recently used first (latest `updatedAt` of an entry that has the tag, else the tag's `createdAt`).
    private var suggestions: [Tag] {
        var lastUsed: [UUID: Date] = [:]
        for entry in entries {
            for id in entry.tagIDs where (lastUsed[id] ?? .distantPast) < entry.updatedAt {
                lastUsed[id] = entry.updatedAt
            }
        }
        let prefix = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let others = tags.filter { tag in
            !model.tagIDs.contains(tag.id)
                && (prefix.isEmpty || tag.name.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil)
        }
        return
            others
            .sorted { (lastUsed[$0.id] ?? $0.createdAt) > (lastUsed[$1.id] ?? $1.createdAt) }
            .prefix(Self.suggestionLimit).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.Day.tagsTitle).font(.footnote).foregroundStyle(Palette.ink2)
            if !dayTags.isEmpty {
                ChipGroup(
                    items: dayTags.map { chip($0, selected: true) },
                    selection: Binding(get: { Set(model.tagIDs) }, set: { _ in }),
                    onToggle: { model.toggleTag($0) })
            }
            let suggested = suggestions
            if !suggested.isEmpty {
                Text(Copy.Tags.recentTitle).font(.footnote).foregroundStyle(Palette.ink2)
                ChipGroup(
                    items: suggested.map { chip($0, selected: false) },
                    selection: Binding(get: { [] }, set: { _ in }),
                    onToggle: { model.toggleTag($0) })
            }
            HStack(spacing: 8) {
                TextField(Copy.Tags.addPlaceholder, text: $newName)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityLabel(Copy.Tags.addLabel)
                    .frame(minHeight: 44)
                Button(action: add) {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                }
                .foregroundStyle(Palette.accent)
                .accessibilityLabel(Copy.Tags.addLabel)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if addFailed {
                Text(Copy.Tags.addFailed).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Button(Copy.Tags.manageLink) { showManage = true }
                .font(.footnote)
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
        }
        .sheet(isPresented: $showManage) {
            NavigationStack {
                TagsView(model: model.makeTagsModel())
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(Copy.Tags.done) { showManage = false } }
                    }
            }
            .tint(Palette.accent)
        }
    }

    private func chip(_ tag: Tag, selected: Bool) -> ChipItem<UUID> {
        ChipItem(id: tag.id, label: tag.name, accessibilityLabel: Copy.Tags.chipLabel(tag.name, selected: selected))
    }

    private func add() {
        let name = newName
        Task {
            switch await model.addTag(named: name) {
            case .added:
                newName = ""
                addFailed = false
            case .blank: break
            case .failed: addFailed = true
            }
        }
    }
}
