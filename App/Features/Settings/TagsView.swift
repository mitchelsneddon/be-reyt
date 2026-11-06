import ReytKit
import SwiftData
import SwiftUI

/// Every tag, alphabetical, with how many days use it. Tap to rename; swipe or edit to delete.
/// Reads with `@Query` (A2 allows reads); writes go through `TagsModel` to `JournalStore`.
struct TagsView: View {
    let model: TagsModel

    @Query private var tags: [Tag]
    // shortcut: loads every entry to count tag use, fine for a personal journal (thousands of rows); precompute past ~10k.
    @Query private var entries: [DailyEntry]
    @State private var renaming: Tag?
    @State private var pendingDelete: Tag?
    @State private var deleteFailed = false

    private var sortedTags: [Tag] {
        tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var usage: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for entry in entries {
            for id in Set(entry.tagIDs) { counts[id, default: 0] += 1 }
        }
        return counts
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                Text(Copy.Tags.manageEmpty)
                    .foregroundStyle(Palette.ink2)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                list
            }
        }
        .background(Palette.paper)
        .navigationTitle(Copy.Tags.manageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !tags.isEmpty { EditButton() } }
        .sheet(item: $renaming) { tag in
            TagRenameSheet(tag: tag, model: model)
        }
        .confirmationDialog(
            pendingDelete.map { Copy.Tags.deleteConfirm($0.name) } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(Copy.Tags.deleteAction, role: .destructive) {
                guard let tag = pendingDelete else { return }
                pendingDelete = nil
                Task { deleteFailed = await !model.delete(tag.id) }
            }
            Button(Copy.Tags.keep, role: .cancel) { pendingDelete = nil }
        }
        .alert(Copy.Tags.deleteFailed, isPresented: $deleteFailed) {
            Button(Copy.Tags.ok, role: .cancel) {}
        }
    }

    private var list: some View {
        let counts = usage
        return List {
            ForEach(sortedTags) { tag in
                Button {
                    renaming = tag
                } label: {
                    HStack {
                        Text(tag.name).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(Copy.Tags.usedOn(counts[tag.id] ?? 0))
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(Copy.Tags.rowLabel(tag.name, days: counts[tag.id] ?? 0))
                .accessibilityHint(Copy.Tags.rowHint)
                .swipeActions {
                    Button(Copy.Tags.deleteAction, role: .destructive) { pendingDelete = tag }
                }
            }
            .onDelete { offsets in
                let current = sortedTags
                if let index = offsets.first { pendingDelete = current[index] }
            }
        }
        .scrollContentBackground(.hidden)
        .tint(Palette.accent)
    }
}

/// Rename one tag. Blank is refused, a clash with another tag shows a calm line and keeps the sheet open.
private struct TagRenameSheet: View {
    let tag: Tag
    let model: TagsModel

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var message: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    init(tag: Tag, model: TagsModel) {
        self.tag = tag
        self.model = model
        _name = State(initialValue: tag.name)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Copy.Tags.renameField, text: $name)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(save)
                        .accessibilityLabel(Copy.Tags.renameField)
                        .frame(minHeight: 44)
                } footer: {
                    if let message { Text(message) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(Copy.Tags.renameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Copy.Tags.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Tags.save, action: save).disabled(trimmed.isEmpty || saving)
                }
            }
            .onChange(of: name) { message = nil }
            .onAppear { focused = true }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium])
    }

    private func save() {
        guard !trimmed.isEmpty, !saving else { return }
        saving = true
        let tagID = tag.id
        let newName = name
        Task {
            let result = await model.rename(tagID, to: newName)
            saving = false
            switch result {
            case .renamed: dismiss()
            case .blank: message = Copy.Tags.renameBlank
            case .taken: message = Copy.Tags.renameTaken(trimmed)
            case .failed: message = Copy.Tags.renameFailed
            }
        }
    }
}
