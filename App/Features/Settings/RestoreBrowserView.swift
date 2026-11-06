import ReytKit
import SwiftUI

/// The snapshots in the backup folder, newest first, for restoring from. Reads the folder without downloading
/// anything; tapping one asks for its passphrase (in the restore sheet) and previews it before anything changes.
struct RestoreBrowserView: View {
    let restore: RestoreCoordinator
    @Environment(BackupManager.self) private var manager

    private enum Load {
        case loading
        case loaded([SnapshotListing])
        case failed
    }

    @State private var load = Load.loading

    var body: some View {
        List {
            switch load {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(Copy.RestoreBrowser.loading).foregroundStyle(Color("inkSecondary"))
                }
                .frame(minHeight: 44)
            case .failed:
                Text(Copy.RestoreBrowser.loadFailed).foregroundStyle(Color("ink"))
                Button(Copy.RestoreBrowser.retry) { Task { await reload() } }.frame(minHeight: 44)
            case .loaded(let rows):
                Section {
                    if rows.isEmpty {
                        Text(Copy.RestoreBrowser.empty).foregroundStyle(Color("inkSecondary"))
                    }
                    ForEach(rows) { row in
                        Button {
                            restore.beginRestore(fromSnapshot: row.ref)
                        } label: {
                            rowLabel(row)
                        }
                        .accessibilityLabel(accessibilityText(row))
                        .frame(minHeight: 44)
                    }
                } footer: {
                    Text(Copy.RestoreBrowser.intro)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("paper"))
        .tint(Color("accent"))
        .navigationTitle(Copy.RestoreBrowser.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func rowLabel(_ row: SnapshotListing) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Copy.RestoreBrowser.day(row.day)).foregroundStyle(Color("ink"))
                Spacer()
                if let size = Copy.RestoreBrowser.size(row.bytes) {
                    Text(size).font(.subheadline).foregroundStyle(Color("inkSecondary"))
                }
            }
            if row.isPreRestore {
                Text(Copy.RestoreBrowser.savedBeforeRestore).font(.footnote).foregroundStyle(Color("ink"))
            }
            Text(location(row)).font(.footnote).foregroundStyle(Color("inkSecondary"))
        }
    }

    private func location(_ row: SnapshotListing) -> String {
        row.isDownloaded ? Copy.RestoreBrowser.onThisPhone : Copy.RestoreBrowser.inICloud
    }

    private func accessibilityText(_ row: SnapshotListing) -> String {
        Copy.RestoreBrowser.rowLabel(
            day: Copy.RestoreBrowser.day(row.day), size: Copy.RestoreBrowser.size(row.bytes),
            kind: row.isPreRestore ? Copy.RestoreBrowser.savedBeforeRestore : nil, location: location(row))
    }

    private func reload() async {
        load = .loading
        do { load = .loaded(try await manager.listSnapshots()) } catch { load = .failed }
    }
}
