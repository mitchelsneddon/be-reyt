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
            if manager.hasDestination, backup.hasPassphrase {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(line)
                }
                Button(manager.isRunning ? Copy.AutoBackup.backingUp : Copy.AutoBackup.backUpNow) {
                    Task { await manager.backUpNow() }
                }
                .disabled(manager.isRunning || !manager.isActive)
                .frame(minHeight: 44, alignment: .leading)
                NavigationLink(Copy.RestoreBrowser.row) { RestoreBrowserView(restore: restore) }
                    .accessibilityHint(Copy.RestoreBrowser.rowHint)
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text(Copy.AutoBackup.title)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if !manager.hasDestination {
                    Text(Copy.AutoBackup.needsFolder)
                } else if !backup.hasPassphrase {
                    Text(Copy.AutoBackup.needsPassphrase)
                }
                if manager.hasDestination, manager.isUbiquitous == false {
                    Text(Copy.AutoBackup.notInICloud).foregroundStyle(Palette.ink)
                }
                Text(Copy.AutoBackup.footer)
            }
        }
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
            HStack {
                Text(manager.hasDestination ? Copy.AutoBackup.folderRow : Copy.AutoBackup.chooseFolder)
                Spacer()
                Text(manager.hasDestination ? (manager.folderName ?? "") : Copy.AutoBackup.off)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .accessibilityHint(Copy.AutoBackup.chooseHint)
    }

    /// The status, most recent fact first. Only what is true: "uploaded" needs iCloud's word for it.
    private var lines: [String] {
        var out: [String] = []
        if let error = manager.index.lastError { out.append(Copy.AutoBackup.error(error)) }
        if let written = manager.index.lastSnapshotWrittenAt {
            out.append(Copy.AutoBackup.lastBackup(written))
        } else {
            out.append(Copy.AutoBackup.noBackupYet)
        }
        switch manager.latestUpload {
        case .uploaded?: out.append(Copy.AutoBackup.uploaded)
        case .uploading?:
            out.append(Copy.AutoBackup.waitingToUpload)
            if let confirmed = manager.index.lastUploadConfirmedAt, confirmed != manager.index.lastSnapshotWrittenAt {
                out.append(Copy.AutoBackup.lastConfirmed(confirmed))
            }
        case .error?: out.append(Copy.AutoBackup.uploadError)
        case .notUbiquitous?, .missing?, nil: break
        }
        if manager.index.pendingChanges { out.append(Copy.AutoBackup.pending) }
        if manager.index.cleanupPaused { out.append(Copy.AutoBackup.cleanupPaused) }
        return out
    }
}
