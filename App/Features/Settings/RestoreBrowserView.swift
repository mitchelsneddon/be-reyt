import ReytKit
import SwiftUI

/// The snapshots in the backup folder, newest first, for restoring from. Reads the folder without downloading
/// anything; tapping one asks for its passphrase (in the restore sheet) and previews it before anything changes.
struct RestoreBrowserView: View {
    let restore: RestoreCoordinator
    @Environment(BackupManager.self) private var manager
    @ScaledMetric(relativeTo: .body) private var chevronHeight: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var locationIcon: CGFloat = 13

    private enum Load {
        case loading
        case loaded([SnapshotListing])
        case failed
    }

    @State private var load = Load.loading

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.paper)
            .tint(Palette.accent)
            .navigationTitle(Copy.RestoreBrowser.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { FlowTitle(text: Copy.RestoreBrowser.title) }
            .task { await reload() }
    }

    @ViewBuilder private var content: some View {
        switch load {
        case .loading:
            FlowBusy(Copy.RestoreBrowser.loading)
        case .failed:
            failed
        case .loaded(let rows) where rows.isEmpty:
            FlowNotice(icon: "folder", text: Copy.RestoreBrowser.empty)
        case .loaded(let rows):
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Palette.border.frame(height: 1) }
                        Button {
                            restore.beginRestore(fromSnapshot: row.ref)
                        } label: {
                            rowLabel(row)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityText(row))
                    }
                }
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
    }

    private var failed: some View {
        VStack(spacing: 20) {
            Text(Copy.RestoreBrowser.loadFailed).brFont(.rowWrapping).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Button(Copy.RestoreBrowser.retry) { Task { await reload() } }
                .buttonStyle(.brOutline)
                .frame(minWidth: 140)
                .fixedSize()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowLabel(_ row: SnapshotListing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Copy.RestoreBrowser.day(row.day)).brFont(.row).foregroundStyle(Palette.ink)
                    if row.isPreRestore { Pill(text: Copy.RestoreBrowser.savedBeforeRestore) }
                }
                HStack(spacing: 5) {
                    if let size = Copy.RestoreBrowser.size(row.bytes) {
                        Text(size)
                        Text("·").accessibilityHidden(true)
                    }
                    Image(systemName: row.isDownloaded ? "iphone" : "icloud")
                        .resizable().scaledToFit().frame(width: locationIcon, height: locationIcon)
                        .accessibilityHidden(true)
                    Text(location(row))
                }
                .brFont(.label).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .resizable().scaledToFit()
                .frame(width: chevronHeight * 0.6, height: chevronHeight)
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
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
