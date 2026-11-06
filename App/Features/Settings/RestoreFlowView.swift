import ReytKit
import SwiftUI

/// The restore sheet: passphrase, preview, explicit confirmation, progress, and calm errors. It reads
/// `RestoreCoordinator.phase`, so it follows the same path the debug launch arguments drive.
struct RestoreFlowView: View {
    let restore: RestoreCoordinator
    @Environment(BackupManager.self) private var manager

    /// What the file card shows: the backup's name, and its size and date when they are known.
    private struct FileInfo: Equatable {
        var name: String
        var detail: String?
    }

    @State private var passphrase = ""
    @State private var showConfirm = false
    @State private var authMessage: String?
    @State private var fileInfo: FileInfo?
    private let passphrases = PassphraseStore()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.paper)
                .navigationTitle(Copy.Restore.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    FlowTitle(text: Copy.Restore.title)
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.Restore.cancel) { restore.cancel() }.brFont(.navAction).disabled(isBusy)
                    }
                }
        }
        .interactiveDismissDisabled(isBusy)
        .tint(Palette.accent)
        .task(id: currentInput) { await loadInfo() }
    }

    private var isBusy: Bool {
        switch restore.phase {
        case .preparing, .restoring, .undoing: true
        default: false
        }
    }

    /// The backup being opened, while the phase still knows it (asking for the passphrase, or failed with a retry).
    private var currentInput: RestoreInput? {
        switch restore.phase {
        case .needsPassphrase(let input): input
        case .failed(_, let retry): retry
        default: nil
        }
    }

    @ViewBuilder private var content: some View {
        switch restore.phase {
        case .idle: EmptyView()
        case .needsPassphrase(let input): passphraseForm(input)
        case .preparing: FlowBusy(Copy.Restore.opening)
        case .ready: previewView
        case .restoring: FlowBusy(Copy.Restore.restoring)
        case .undoing: FlowBusy(Copy.Restore.undoing)
        case .failed(let failure, let retry): failureView(failure, retry: retry)
        }
    }

    // MARK: File card

    private func fileCard(name: String, detail: String?) -> some View {
        HStack(spacing: 14) {
            IconTile(systemName: "doc")
            VStack(alignment: .leading, spacing: 2) {
                Text(name).brFont(.cardTitle).foregroundStyle(Palette.ink)
                if let detail { Text(detail).brFont(.label).foregroundStyle(Palette.ink2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var card: some View {
        if let fileInfo {
            fileCard(name: fileInfo.name, detail: fileInfo.detail)
        } else if let name = restore.preview?.sourceName {
            fileCard(name: name, detail: nil)
        }
    }

    private func loadInfo() async {
        guard let input = currentInput else { return }
        switch input {
        case .file(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            fileInfo = FileInfo(
                name: url.lastPathComponent,
                detail: Self.detail(
                    size: Copy.Export.fileSize(values?.fileSize),
                    date: values?.contentModificationDate.map(Copy.Restore.fileDate)))
        case .snapshot(let ref):
            fileInfo = FileInfo(name: ref.name, detail: nil)
            guard let row = try? await manager.listSnapshots().first(where: { $0.ref == ref }) else { return }
            fileInfo = FileInfo(
                name: ref.name,
                detail: Self.detail(
                    size: Copy.Export.fileSize(row.bytes),
                    date: Copy.Restore.fileDate(row.day.date(in: .current))))
        }
    }

    private static func dayText(_ key: String) -> String {
        DateKey(key).map { Copy.Restore.fileDate($0.date(in: .current)) } ?? key
    }

    private static func detail(size: String?, date: String?) -> String? {
        let parts = [size, date].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Passphrase

    private func passphraseForm(_ input: RestoreInput) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                card
                Text(isSnapshot(input) ? Copy.RestoreBrowser.enterPassphrase : Copy.Restore.enterPassphrase)
                    .brFont(.body).foregroundStyle(Palette.ink)
                BRSecureField(label: Copy.Restore.passphraseField, text: $passphrase)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(Copy.Restore.open) {
                let entered = passphrase
                Task { await restore.open(input, passphrase: entered) }
            }
            .buttonStyle(.brPrimary)
            .disabled(passphrase.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .onAppear { if passphrase.isEmpty { passphrase = passphrases.stored() ?? "" } }
    }

    private func isSnapshot(_ input: RestoreInput) -> Bool {
        if case .snapshot = input { return true }
        return false
    }

    // MARK: Preview

    @ViewBuilder private var previewView: some View {
        if let preview = restore.preview {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    card
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Copy.Restore.previewTitle).brFont(.dayNum).foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(Copy.Restore.previewIntro).brFont(.label).foregroundStyle(Palette.ink2)
                            .padding(.bottom, 6)
                        infoRows(preview)
                    }
                    if preview.skippedPhotos > 0 {
                        Text(Copy.Export.skipped(preview.skippedPhotos)).brFont(.banner)
                            .foregroundStyle(Palette.ink2)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.accent)
                            .accessibilityHidden(true)
                        Text(Copy.Restore.confirmMessage).brFont(.rowWrapping).foregroundStyle(Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                    if let authMessage { ProblemLine(text: authMessage) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        if await Reauthenticator.confirm(reason: Copy.Restore.reauthReason) {
                            showConfirm = true
                        } else {
                            authMessage = Copy.Restore.reauthFailed
                        }
                    }
                } label: {
                    Text(Copy.Restore.replace).multilineTextAlignment(.center).padding(.vertical, 8)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.brPrimary)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
            .confirmationDialog(Copy.Restore.confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
                Button(Copy.Restore.confirmAction, role: .destructive) { Task { await restore.confirmRestore() } }
                Button(Copy.Restore.cancel, role: .cancel) {}
            } message: {
                Text(Copy.Restore.confirmMessage)
            }
        }
    }

    private func infoRows(_ preview: RestorePreview) -> some View {
        var rows = [
            Copy.Restore.days(preview.counts.entries), Copy.Restore.photos(preview.counts.attachments),
            Copy.Restore.tags(preview.counts.tags), Copy.Restore.plans(preview.counts.intentions),
        ].map { ($0, Palette.ink) }
        if let range = preview.dateRange {
            rows.append(
                (Copy.Restore.range(first: Self.dayText(range.first), last: Self.dayText(range.last)), Palette.ink2))
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Palette.border.frame(height: 1) }
                Text(row.0).brFont(.row).foregroundStyle(row.1)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    // MARK: Failure

    private func failureView(_ failure: RestoreFailure, retry: RestoreInput?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            card
            Text(Copy.Restore.failure(failure)).brFont(.body).foregroundStyle(Palette.danger)
            if let retry {
                Button(Copy.Restore.tryAgain) { restore.retry(retry) }.buttonStyle(.brOutline)
                Button(Copy.Restore.close) { restore.cancel() }.buttonStyle(.brSecondary)
            } else {
                Button(Copy.Restore.close) { restore.cancel() }.buttonStyle(.brOutline)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }
}
