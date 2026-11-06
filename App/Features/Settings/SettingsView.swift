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
    #if DEBUG
        // Simulator-only: `-openTags`, `-openReadableExport`, `-openDeleteAll` (or `-openDeleteAllConfirm`) push that screen.
        @State private var debugTags =
            CommandLine.arguments.contains("-openTags") || CommandLine.arguments.contains("-openTagsRename")
        @State private var debugExport = CommandLine.arguments.contains("-openReadableExport")
        // `-openRestoreBrowser` pushes the backup list; `-openPassphrase set|change` opens that sheet;
        // `-debugExportState working|saved|savedSkipped|failed` shows the inline export status.
        @State private var debugBrowser = CommandLine.arguments.contains("-openRestoreBrowser")
        @State private var debugDelete =
            CommandLine.arguments.contains("-openDeleteAll") || CommandLine.arguments.contains("-openDeleteAllConfirm")
    #endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.Settings.title)
                    .brFont(.largeTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(EdgeInsets(top: 18, leading: 28, bottom: 22, trailing: 24))
                ScrollViewReader { proxy in
                    list
                        #if DEBUG
                            .task {
                                // Simulator-only: `-scrollSettingsToBottom` shows the end of the list;
                                // `-scrollSettingsTo <id>` (backups, passphrase) shows that section.
                                let args = CommandLine.arguments
                                if let i = args.firstIndex(of: "-scrollSettingsTo"), args.indices.contains(i + 1) {
                                    try? await Task.sleep(for: .seconds(1))
                                    proxy.scrollTo(args[i + 1], anchor: .top)
                                    return
                                }
                                guard args.contains("-scrollSettingsToBottom") else { return }
                                try? await Task.sleep(for: .seconds(1))
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.paper)
            .completionNotes()
            .navigationTitle(Copy.Settings.title)
            .toolbar(.hidden, for: .navigationBar)
            #if DEBUG
                .navigationDestination(isPresented: $debugTags) { TagsView(model: tags) }
                .navigationDestination(isPresented: $debugExport) { ReadableExportView(host: backup.host) }
                .navigationDestination(isPresented: $debugDelete) { DeleteAllView() }
                .navigationDestination(isPresented: $debugBrowser) { RestoreBrowserView(restore: restore) }
            #endif
        }
    }

    private var list: some View {
        List {
            ReminderSection()
            Section {
                NavigationLink {
                    TagsView(model: tags)
                } label: {
                    SettingsRowLabel(title: Copy.Tags.settingsRow, icon: "number")
                }
            } header: {
                SettingsHeader(Copy.Tags.journalSection)
            }
            .settingsRows()
            AppLockSection()
            HealthSection()
            OnDeviceAISection()
            BackupStatusView(backup: backup, restore: restore).id("backups")
            Section {
                passphraseRow
                exportRow
                Button {
                    showImporter = true
                } label: {
                    SettingsRowLabel(title: Copy.Settings.restoreRow, icon: "square.and.arrow.down", chevron: true)
                }
                if restore.undoAvailable {
                    Button {
                        showUndoConfirm = true
                    } label: {
                        SettingsAction(title: Copy.Settings.undoRow, icon: "arrow.uturn.backward")
                    }
                    .accessibilityHint(Copy.Settings.undoHint)
                }
                ExportStatus(backup: backup, authMessage: authMessage)
            } header: {
                SettingsHeader(Copy.Settings.backupSection)
            }
            .settingsRows()
            .id("passphrase")
            Section {
                NavigationLink {
                    ReadableExportView(host: backup.host)
                } label: {
                    SettingsRowLabel(title: Copy.ReadableExport.row, icon: "doc.text")
                }
                .accessibilityHint(Copy.ReadableExport.rowHint)
            } header: {
                SettingsHeader(Copy.Hub.readableSection)
            }
            .settingsRows()
            ImportSection { showJournalPicker = true }
            PrivacySection()
            AboutSection()
            DeleteAllSection().id("bottom")
        }
        .listSectionSpacing(28)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .tint(Palette.accent)
        .onAppear {
            backup.refresh()
            restore.refreshUndoAvailability()
            #if DEBUG
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "-openPassphrase"), args.indices.contains(i + 1) {
                    passphraseSheet = args[i + 1] == "change" ? .change : .set
                }
                if let i = args.firstIndex(of: "-debugExportState"), args.indices.contains(i + 1) {
                    backup.debugShowExport(args[i + 1])
                }
            #endif
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
            SettingsRowLabel(
                title: Copy.Settings.passphraseRow, icon: "key",
                value: backup.hasPassphrase ? Copy.Settings.passphraseSet : Copy.Settings.passphraseNotSet,
                chevron: true)
        }
    }

    private var exportRow: some View {
        Button {
            if backup.hasPassphrase {
                Task { await backup.export() }
            } else {
                passphraseSheet = .set
            }
        } label: {
            if backup.exportState == .working {
                SettingsAction(title: Copy.Settings.exportRow, icon: "square.and.arrow.up", busy: true)
            } else {
                SettingsRowLabel(
                    title: Copy.Settings.exportRow, icon: "square.and.arrow.up",
                    value: backup.hasPassphrase ? nil : Copy.Settings.exportRowNeedsPassphrase, chevron: true)
            }
        }
        .disabled(backup.exportState == .working)
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
            SettingsRowLabel(
                title: Copy.Hub.lockRow, icon: "lock", value: hasPasscode ? Copy.Hub.lockOn : Copy.Hub.lockOff)
            if !hasPasscode { SettingsNote(text: Copy.Hub.lockNoPasscode, color: Palette.ink) }
        } header: {
            SettingsHeader(Copy.Hub.lockSection)
        }
        .settingsRows()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
        }
    }
}

/// Static statements of what the app does and doesn't do with the journal.
struct PrivacySection: View {
    private static let icons = ["iphone", "eye.slash", "sparkles", "clock"]

    var body: some View {
        Section {
            ForEach(Array(zip(Self.icons, Copy.Hub.privacyLines)), id: \.1) { icon, line in
                SettingsRowLabel(title: line, icon: icon, wrapping: true)
            }
        } header: {
            SettingsHeader(Copy.Hub.privacySection)
        }
        .settingsRows()
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
            SettingsRowLabel(title: Copy.Hub.version, icon: "info.circle", value: version)
            if let expiry = provisioning.expirationDate {
                SettingsRowLabel(
                    title: Copy.Hub.signedUntil, icon: "calendar",
                    value: Copy.Dates.format(expiry, month: .abbreviated, year: true))
            }
        } header: {
            SettingsHeader(Copy.Hub.aboutSection)
        }
        .settingsRows()
    }
}

// MARK: - Shared settings pieces

/// A section header: DM Sans 13, tracking 0.4, ink2, lowercase as written.
struct SettingsHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).brFont(.sectionHeader).foregroundStyle(Palette.ink2).textCase(nil)
    }
}

extension View {
    /// Card row background and border-coloured separators for every row of a settings section.
    func settingsRows() -> some View {
        listRowBackground(Palette.card).listRowSeparatorTint(Palette.border)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

/// An accent action row: tile-less (aligned with the titles) or with a tile; `busy` swaps the tile for a spinner.
struct SettingsAction: View {
    let title: String
    var icon: String?
    var busy = false

    var body: some View {
        HStack(spacing: 12) {
            if busy {
                IconTile { ProgressRing(size: 18, lineWidth: 2.5) }
            } else if let icon {
                IconTile(systemName: icon)
            } else {
                IconTile(systemName: "circle").hidden()
            }
            Text(title).brFont(.row).foregroundStyle(busy ? Palette.ink2 : Palette.accent)
            Spacer(minLength: 8)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A short line inside a section: guidance in ink2, a consequence in ink, or a problem in danger with an icon.
struct SettingsNote: View {
    let text: String
    var color: Color = Palette.ink2
    var problem = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: "circle").hidden()
                .overlay {
                    if problem {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Palette.danger)
                            .accessibilityLabel(Copy.Settings.problem)
                    }
                }
            Text(text).brFont(.banner).foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
