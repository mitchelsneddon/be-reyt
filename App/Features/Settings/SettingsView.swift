import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

/// The settings tab: a calm list of sections, in the order they matter.
struct SettingsView: View {
    let backup: BackupSettingsModel
    let restore: RestoreCoordinator
    let tags: TagsModel
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
        NavigationStack {
            ScrollViewReader { proxy in
                list
                    #if DEBUG
                        .task {
                            // Simulator-only: `-scrollSettingsToBottom` shows the end of the list.
                            guard CommandLine.arguments.contains("-scrollSettingsToBottom") else { return }
                            try? await Task.sleep(for: .seconds(1))
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    #endif
            }
            .navigationTitle(Copy.Settings.title)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var list: some View {
        List {
            ReminderSection()
            Section {
                NavigationLink(Copy.Tags.settingsRow) { TagsView(model: tags) }
                    .frame(minHeight: 44, alignment: .leading)
            } header: {
                Text(Copy.Tags.journalSection)
            }
            AppLockSection()
            HealthSection()
            OnDeviceAISection()
            BackupStatusView(backup: backup, restore: restore)
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
                    if let note = statusNote { Text(note).foregroundStyle(Palette.ink) }
                }
            }
            Section {
                NavigationLink(Copy.ReadableExport.row) { ReadableExportView(host: backup.host) }
                    .accessibilityHint(Copy.ReadableExport.rowHint)
                    .frame(minHeight: 44, alignment: .leading)
            } header: {
                Text(Copy.Hub.readableSection)
            } footer: {
                Text(Copy.ReadableExport.notEncrypted)
            }
            ImportSection { showJournalPicker = true }
            PrivacySection()
            AboutSection()
            DeleteAllSection().id("bottom")
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .tint(Palette.accent)
        .onAppear {
            backup.refresh()
            restore.refreshUndoAvailability()
        }
        .sheet(item: $passphraseSheet) { sheet in
            PassphraseView(backup: backup, isChange: sheet == .change)
        }
        .sheet(isPresented: restoreSheetBinding) { RestoreFlowView(restore: restore) }
        // One file importer/exporter per host view: several on the same view are unreliable (only one presents).
        .background(
            Color.clear.fileImporter(isPresented: $showImporter, allowedContentTypes: UTType.restoreSources) { result in
                if case .success(let url) = result { restore.beginRestore(from: url) }
            }
        )
        .background(
            Color.clear.fileImporter(isPresented: $showJournalPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { journalImporter.begin(folder: url) }
            }
        )
        .background(
            Color.clear.fileExporter(
                isPresented: Bindable(backup).showExporter, item: backup.file, contentTypes: [.beReytArchive],
                defaultFilename: backup.suggestedName,
                onCompletion: { backup.exporterFinished($0) }, onCancellation: { backup.exporterCancelled() }
            )
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
                    .foregroundStyle(Palette.ink2)
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
                    Text(Copy.Settings.exportRowNeedsPassphrase).font(.footnote).foregroundStyle(Palette.ink2)
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

/// Read-only: the lock is always on. Warns when the phone has no passcode, because then it can't lock.
struct AppLockSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

    var body: some View {
        Section {
            LabeledContent(Copy.Hub.lockRow) {
                Text(hasPasscode ? Copy.Hub.lockOn : Copy.Hub.lockOff)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        } header: {
            Text(Copy.Hub.lockSection)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.Hub.lockFooter)
                if !hasPasscode { Text(Copy.Hub.lockNoPasscode).foregroundStyle(Palette.ink) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
        }
    }
}

/// Static statements of what the app does and doesn't do with the journal.
struct PrivacySection: View {
    var body: some View {
        Section {
            ForEach(Copy.Hub.privacyLines, id: \.self) { line in
                Text(line).frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text(Copy.Hub.privacySection)
        }
    }
}

/// Version, build, and when this install stops opening.
struct AboutSection: View {
    private let provisioning = ProvisioningInfo.load()

    private var version: String {
        let info = Bundle.main.infoDictionary
        return Copy.Hub.versionValue(
            version: info?["CFBundleShortVersionString"] as? String ?? "0",
            build: info?["CFBundleVersion"] as? String ?? "0")
    }

    var body: some View {
        Section {
            LabeledContent(Copy.Hub.version) { Text(version) }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            if let expiry = provisioning.expirationDate {
                LabeledContent(Copy.Hub.signedUntil) {
                    Text(expiry, format: .dateTime.day().month(.wide).year().locale(Locale(identifier: "en_GB")))
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(Copy.Hub.aboutSection)
        } footer: {
            if provisioning.expirationDate != nil { Text(Copy.Hub.reinstallNote) }
        }
    }
}
