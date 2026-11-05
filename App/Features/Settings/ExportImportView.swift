import SwiftUI
import UniformTypeIdentifiers

/// Backup passphrase, manual export, restore from a file, and undo of the last restore.
struct ExportImportView: View {
    let backup: BackupSettingsModel
    let restore: RestoreCoordinator
    @Environment(AppleJournalImporter.self) private var journalImporter

    private enum PassphraseSheet: String, Identifiable {
        case set, change
        var id: String { rawValue }
    }

    @State private var passphraseSheet: PassphraseSheet?
    @State private var showImporter = false
    @State private var showJournalPicker = false
    @State private var showUndoConfirm = false
    @State private var authMessage: String?

    var body: some View {
        List {
            ReminderSection()
            HealthSection()
            ImportSection { showJournalPicker = true }
            Section {
                passphraseRow
                exportRow
                Button(Copy.Settings.restoreRow) { showImporter = true }
                    .frame(minHeight: 44, alignment: .leading)
                if restore.undoAvailable {
                    Button(Copy.Settings.undoRow) { showUndoConfirm = true }
                        .accessibilityHint(Copy.Settings.undoHint)
                        .frame(minHeight: 44, alignment: .leading)
                }
            } header: {
                Text(Copy.Settings.backupSection)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.Settings.backupFooter)
                    if let note = statusNote { Text(note).foregroundStyle(Color("ink")) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("paper"))
        .tint(Color("accent"))
        .onAppear {
            backup.refresh()
            restore.refreshUndoAvailability()
        }
        .sheet(item: $passphraseSheet) { sheet in
            PassphraseView(backup: backup, isChange: sheet == .change)
        }
        .sheet(isPresented: restoreSheetBinding) { RestoreFlowView(restore: restore) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: UTType.restoreSources) { result in
            if case .success(let url) = result { restore.beginRestore(from: url) }
        }
        .fileImporter(isPresented: $showJournalPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { journalImporter.begin(folder: url) }
        }
        .fileExporter(
            isPresented: Bindable(backup).showExporter, item: backup.file, contentTypes: [.beReytArchive],
            defaultFilename: backup.suggestedName,
            onCompletion: { backup.exporterFinished($0) }, onCancellation: { backup.exporterCancelled() }
        )
        .confirmationDialog(Copy.Restore.undoConfirmTitle, isPresented: $showUndoConfirm, titleVisibility: .visible) {
            Button(Copy.Restore.undoAction, role: .destructive) { undo() }
            Button(Copy.Restore.cancel, role: .cancel) {}
        } message: {
            Text(Copy.Restore.undoConfirmMessage)
        }
    }

    private var restoreSheetBinding: Binding<Bool> {
        Binding(get: { restore.phase != .idle }, set: { if !$0 { restore.cancel() } })
    }

    private var passphraseRow: some View {
        Button {
            if backup.hasPassphrase {
                Task {
                    if await Reauthenticator.confirm(reason: Copy.Passphrase.reauthReason) {
                        passphraseSheet = .change
                    } else {
                        authMessage = Copy.Export.reauthFailed
                    }
                }
            } else {
                passphraseSheet = .set
            }
        } label: {
            HStack {
                Text(Copy.Settings.passphraseRow)
                Spacer()
                Text(backup.hasPassphrase ? Copy.Settings.passphraseSet : Copy.Settings.passphraseNotSet)
                    .foregroundStyle(Color("inkSecondary"))
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var exportRow: some View {
        Button {
            if backup.hasPassphrase {
                Task { await backup.export() }
            } else {
                passphraseSheet = .set
            }
        } label: {
            HStack {
                Text(Copy.Settings.exportRow)
                Spacer()
                if backup.exportState == .working {
                    ProgressView()
                } else if !backup.hasPassphrase {
                    Text(Copy.Settings.exportRowNeedsPassphrase).font(.footnote).foregroundStyle(Color("inkSecondary"))
                }
            }
        }
        .disabled(backup.exportState == .working)
        .frame(minHeight: 44)
    }

    private var statusNote: String? {
        if backup.exportState == .working { return Copy.Export.working }
        if case .failed(let message) = backup.exportState { return message }
        return authMessage ?? backup.exportNote
    }

    private func undo() {
        Task {
            guard await Reauthenticator.confirm(reason: Copy.Restore.reauthReason) else {
                authMessage = Copy.Restore.reauthFailed
                return
            }
            try? await restore.undoLastRestore()  // a failure shows in the restore sheet
        }
    }
}
