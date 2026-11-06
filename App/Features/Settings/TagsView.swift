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
    @Environment(\.editMode) private var editMode

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
                emptyState
            } else {
                list
            }
        }
        .background(Palette.paper)
        .navigationTitle(Copy.Tags.manageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(Copy.Tags.manageTitle).brFont(.navTitle).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            if !tags.isEmpty { ToolbarItem(placement: .primaryAction) { editButton } }
        }
        .tint(Palette.accent)
        #if DEBUG
            .task {
                // Simulator-only: `-openTagsRename` opens the rename sheet for the first tag.
                guard CommandLine.arguments.contains("-openTagsRename") else { return }
                try? await Task.sleep(for: .seconds(2))
                renaming = sortedTags.first
            }
        #endif
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

    private var editButton: some View {
        let editing = editMode?.wrappedValue.isEditing == true
        return Button(editing ? Copy.Tags.done : Copy.Tags.edit) {
            withAnimation { editMode?.wrappedValue = editing ? .inactive : .active }
        }
        .brFont(.navAction)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("#")
                .brFont(.onboardingTitle)
                .foregroundStyle(Palette.accent)
                .frame(width: 72, height: 72)
                .background(Palette.accentSoft, in: Circle())
                .accessibilityHidden(true)
            Text(Copy.Tags.manageEmpty).brFont(.navAction).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        let counts = usage
        return List {
            Section {
                ForEach(sortedTags) { tag in
                    Button {
                        renaming = tag
                    } label: {
                        HStack(spacing: 12) {
                            Text(tag.name).brFont(.row).foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Copy.Tags.usedOn(counts[tag.id] ?? 0))
                                .brFont(.rowWrapping).foregroundStyle(Palette.ink2)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.ink3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Copy.Tags.rowLabel(tag.name, days: counts[tag.id] ?? 0))
                    .accessibilityHint(Copy.Tags.rowHint)
                    .swipeActions {
                        Button(Copy.Tags.deleteAction, role: .destructive) { pendingDelete = tag }
                            .tint(Palette.danger)
                    }
                }
                .onDelete { offsets in
                    let current = sortedTags
                    if let index = offsets.first { pendingDelete = current[index] }
                }
            }
            .settingsRows()
        }
        .scrollContentBackground(.hidden)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.Tags.renameField).brFont(.sectionHeader).foregroundStyle(Palette.ink2)
                    .accessibilityHidden(true)
                TextField(Copy.Tags.renameField, text: $name)
                    .brFont(.navAction)
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .accessibilityLabel(Copy.Tags.renameField)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(message == nil ? Palette.border : Palette.danger, lineWidth: 1)
                    )
                if let message {
                    Text(message).brFont(.banner).foregroundStyle(Palette.danger)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 0, trailing: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.paper)
            .navigationTitle(Copy.Tags.renameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Copy.Tags.renameTitle).brFont(.navTitle).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Tags.cancel) { dismiss() }.brFont(.navAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Tags.save, action: save).brFont(.navActionBold).disabled(trimmed.isEmpty || saving)
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
