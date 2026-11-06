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
    @State private var adding = false
    @FocusState private var addFocused: Bool

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
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 8) {
                ForEach(dayTags) { tag in
                    Button {
                        model.toggleTag(tag.id)
                    } label: {
                        Text("# \(tag.name)")
                            .brFont(.chip)
                            .foregroundStyle(Palette.accentText)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 13)
                            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Copy.Tags.chipLabel(tag.name, selected: true))
                    .accessibilityAddTraits(.isSelected)
                }
                addPill
            }
            let suggested = suggestions
            if !suggested.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(suggested) { tag in
                        Button {
                            model.toggleTag(tag.id)
                        } label: {
                            Text(tag.name)
                                .brFont(.chip)
                                .foregroundStyle(Palette.ink)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 13)
                                .background(Palette.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Copy.Tags.chipLabel(tag.name, selected: false))
                    }
                }
            }
            if addFailed {
                Text(Copy.Tags.addFailed).brFont(.label).foregroundStyle(Palette.ink2)
            }
            Button(Copy.Tags.manageLink) { showManage = true }
                .brFont(.label)
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

    /// The dashed "+ add a tag" pill; tapping it turns it into the text field (same add flow as before).
    @ViewBuilder private var addPill: some View {
        let dashed = RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Palette.ink3, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        if adding {
            TextField(Copy.Tags.addPlaceholder, text: $newName)
                .brFont(.chip)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($addFocused)
                .onSubmit(add)
                .onChange(of: addFocused) { _, focused in
                    if !focused, newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { adding = false }
                }
                .accessibilityLabel(Copy.Tags.addLabel)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(minWidth: 140, minHeight: 44)
                .overlay(dashed.frame(minHeight: 32))
        } else {
            Button {
                adding = true
                addFocused = true
            } label: {
                Text(Copy.Tags.addAffordance)
                    .brFont(.chip)
                    .foregroundStyle(Palette.ink2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .overlay(dashed)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.Tags.addLabel)
        }
    }

    private func add() {
        let name = newName
        Task {
            switch await model.addTag(named: name) {
            case .added:
                newName = ""
                addFailed = false
                adding = false
            case .blank: break
            case .failed: addFailed = true
            }
        }
    }
}
