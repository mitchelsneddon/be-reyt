import SwiftUI
import UniformTypeIdentifiers

/// The "automatic backups" part of the backup settings: choose the folder, see what happened last, and back up
/// now. Never claims "uploaded" unless iCloud says so for the latest snapshot and its photos.
struct BackupStatusView: View {
    let backup: BackupSettingsModel
    let restore: RestoreCoordinator
    @Environment(BackupManager.self) private var manager
    @State private var showPicker = false

    var body: some View {
        Section {
            folderRow
            if manager.hasDestination {
                if backup.hasPassphrase {
                    statusRows
                } else {
                    SettingsNote(text: Copy.AutoBackup.needsPassphrase, color: Palette.ink, problem: true)
                }
                if manager.isUbiquitous == false {
                    SettingsNote(text: Copy.AutoBackup.notInICloud, color: Palette.ink)
                }
                if backup.hasPassphrase {
                    Button {
                        Task { await manager.backUpNow() }
                    } label: {
                        SettingsAction(
                            title: manager.isRunning ? Copy.AutoBackup.backingUp : Copy.AutoBackup.backUpNow,
                            icon: "arrow.clockwise", busy: manager.isRunning)
                    }
                    .disabled(manager.isRunning || !manager.isActive)
                    NavigationLink {
                        RestoreBrowserView(restore: restore)
                    } label: {
                        SettingsRowLabel(title: Copy.RestoreBrowser.row, icon: "clock.arrow.circlepath")
                    }
                    .accessibilityHint(Copy.RestoreBrowser.rowHint)
                }
            }
        } header: {
            SettingsHeader(Copy.AutoBackup.title)
        }
        .settingsRows()
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await manager.chooseFolder(url) } }
        }
        .task {
            await manager.refreshDestination()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await manager.refreshUploadStatus()
            }
        }
    }

    private var folderRow: some View {
        Button {
            showPicker = true
        } label: {
            SettingsRowLabel(
                title: manager.hasDestination ? Copy.AutoBackup.folderRow : Copy.AutoBackup.chooseFolder,
                icon: "folder",
                value: manager.hasDestination ? (manager.folderName ?? "") : Copy.AutoBackup.off,
                chevron: true)
        }
        .accessibilityHint(Copy.AutoBackup.chooseHint)
    }

    /// The status, most recent fact first. Only what is true: "uploaded" needs iCloud's word for it.
    @ViewBuilder private var statusRows: some View {
        if let error = manager.index.lastError {
            SettingsNote(text: Copy.AutoBackup.error(error), color: Palette.danger, problem: true)
        }
        SettingsRowLabel(
            title: Copy.AutoBackup.lastBackupRow, icon: "clock",
            value: manager.index.lastSnapshotWrittenAt.map { Copy.AutoBackup.lastBackup($0) }
                ?? Copy.AutoBackup.noBackupYet)
        switch manager.latestUpload {
        case .uploaded?:
            SettingsRowLabel(
                title: Copy.AutoBackup.icloudRow, icon: "icloud", value: Copy.AutoBackup.uploaded, dot: Palette.ok)
        case .uploading?:
            SettingsRowLabel(
                title: Copy.AutoBackup.icloudRow, icon: "icloud", value: Copy.AutoBackup.waitingToUpload,
                dot: Palette.warn)
            if let confirmed = manager.index.lastUploadConfirmedAt, confirmed != manager.index.lastSnapshotWrittenAt {
                SettingsRowLabel(
                    title: Copy.AutoBackup.lastConfirmedRow, icon: "icloud",
                    value: Copy.AutoBackup.lastBackup(confirmed))
            }
        case .error?:
            SettingsNote(text: Copy.AutoBackup.uploadError, color: Palette.danger, problem: true)
        case .notUbiquitous?, .missing?, nil: EmptyView()
        }
        if manager.index.pendingChanges { SettingsNote(text: Copy.AutoBackup.pending) }
        if manager.index.cleanupPaused { SettingsNote(text: Copy.AutoBackup.cleanupPaused) }
    }
}
