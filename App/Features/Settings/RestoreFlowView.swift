import ReytKit
import SwiftUI

/// The restore sheet: passphrase, preview, explicit confirmation, progress, and calm errors. It reads
/// `RestoreCoordinator.phase`, so it follows the same path the debug launch arguments drive.
struct RestoreFlowView: View {
    let restore: RestoreCoordinator

    @State private var passphrase = ""
    @State private var showConfirm = false
    @State private var authMessage: String?
    private let passphrases = PassphraseStore()

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.paper)
                .navigationTitle(Copy.Restore.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.Restore.cancel) { restore.cancel() }.disabled(isBusy)
                    }
                }
        }
        .interactiveDismissDisabled(isBusy)
        .tint(Palette.accent)
    }

    private var isBusy: Bool {
        switch restore.phase {
        case .preparing, .restoring, .undoing: true
        default: false
        }
    }

    @ViewBuilder private var content: some View {
        switch restore.phase {
        case .idle: EmptyView()
        case .needsPassphrase(let input): passphraseForm(input)
        case .preparing: progress(Copy.Restore.opening)
        case .ready: previewView
        case .restoring: progress(Copy.Restore.restoring)
        case .undoing: progress(Copy.Restore.undoing)
        case .failed(let failure, let retry): failureView(failure, retry: retry)
        }
    }

    private func passphraseForm(_ input: RestoreInput) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isSnapshot(input) ? Copy.RestoreBrowser.enterPassphrase : Copy.Restore.enterPassphrase)
                .font(.body).foregroundStyle(Palette.ink)
            SecureField(Copy.Restore.passphraseField, text: $passphrase)
                .textContentType(.password)
                .padding(12)
                .background(Palette.ink2.opacity(0.12), in: .rect(cornerRadius: 10))
                .frame(minHeight: 44)
            Button(Copy.Restore.open) {
                let entered = passphrase
                Task { await restore.open(input, passphrase: entered) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(passphrase.isEmpty)
            .frame(minHeight: 44)
        }
        .padding(.top, 24)
        .onAppear { if passphrase.isEmpty { passphrase = passphrases.stored() ?? "" } }
    }

    private func isSnapshot(_ input: RestoreInput) -> Bool {
        if case .snapshot = input { return true }
        return false
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(text).font(.body).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var previewView: some View {
        if let preview = restore.preview {
            VStack(alignment: .leading, spacing: 12) {
                Text(Copy.Restore.previewTitle).font(.system(.title2, design: .serif)).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.Restore.previewIntro).font(.footnote).foregroundStyle(Palette.ink2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.Restore.days(preview.counts.entries))
                    Text(Copy.Restore.photos(preview.counts.attachments))
                    Text(Copy.Restore.tags(preview.counts.tags))
                    Text(Copy.Restore.plans(preview.counts.intentions))
                    if let range = preview.dateRange {
                        Text(Copy.Restore.range(first: range.first, last: range.last))
                            .foregroundStyle(Palette.ink2)
                    }
                }
                .font(.body).foregroundStyle(Palette.ink)
                if preview.skippedPhotos > 0 {
                    Text(Copy.Export.skipped(preview.skippedPhotos)).font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                if let authMessage { Text(authMessage).font(.footnote).foregroundStyle(Palette.ink) }
                Spacer(minLength: 24)
                Button(Copy.Restore.replace) {
                    Task {
                        if await Reauthenticator.confirm(reason: Copy.Restore.reauthReason) {
                            showConfirm = true
                        } else {
                            authMessage = Copy.Restore.reauthFailed
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
            .padding(.top, 24)
            .confirmationDialog(Copy.Restore.confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
                Button(Copy.Restore.confirmAction, role: .destructive) { Task { await restore.confirmRestore() } }
                Button(Copy.Restore.cancel, role: .cancel) {}
            } message: {
                Text(Copy.Restore.confirmMessage)
            }
        }
    }

    private func failureView(_ failure: RestoreFailure, retry: RestoreInput?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Copy.Restore.failure(failure)).font(.body).foregroundStyle(Palette.ink)
            if let retry {
                Button(Copy.Restore.tryAgain) { restore.retry(retry) }.frame(minHeight: 44)
            }
            Button(Copy.Restore.close) { restore.cancel() }.frame(minHeight: 44)
        }
        .padding(.top, 24)
    }
}
