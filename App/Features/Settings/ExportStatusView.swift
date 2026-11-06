import SwiftUI

/// The inline status under the backup rows: gathering, saved (with the file and its size), or a problem.
struct ExportStatus: View {
    let backup: BackupSettingsModel
    let authMessage: String?

    var body: some View {
        if backup.exportState == .working {
            HStack(spacing: 12) {
                IconTile { ProgressRing(size: 18, lineWidth: 2.5) }
                Text(Copy.Export.working).brFont(.row).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
        } else if case .failed(let message) = backup.exportState {
            SettingsNote(text: message, color: Palette.danger, problem: true)
        } else if let authMessage {
            SettingsNote(text: authMessage, color: Palette.danger, problem: true)
        } else if let saved = backup.savedExport {
            savedView(saved)
        }
    }

    private func savedView(_ saved: BackupSettingsModel.SavedExport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok).accessibilityHidden(true)
                Text(Copy.Export.saved).brFont(.navTitle).foregroundStyle(Palette.ink)
            }
            HStack(spacing: 12) {
                Image(systemName: "doc").foregroundStyle(Palette.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name).brFont(.cardTitle).foregroundStyle(Palette.ink)
                    if let size = Copy.Export.fileSize(saved.bytes) {
                        Text(size).brFont(.label).foregroundStyle(Palette.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            if saved.skippedPhotos > 0 {
                Text(Copy.Export.skipped(saved.skippedPhotos)).brFont(.banner).foregroundStyle(Palette.ink2)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}
