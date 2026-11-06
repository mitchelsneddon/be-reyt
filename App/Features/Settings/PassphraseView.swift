import SwiftUI

/// Set or change the backup passphrase: the only rule is 8 characters. Changing asks for the current one.
struct PassphraseView: View {
    let backup: BackupSettingsModel
    let isChange: Bool

    private enum Field { case current, new, confirm }

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var entry = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var invalid: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(Copy.Passphrase.warning).brFont(.body).foregroundStyle(Palette.ink)
                    VStack(alignment: .leading, spacing: 18) {
                        if isChange {
                            BRSecureField(
                                label: Copy.Passphrase.current, text: $current, contentType: .password,
                                invalid: invalid == .current)
                        }
                        BRSecureField(
                            label: Copy.Passphrase.new, text: $entry, contentType: .newPassword,
                            invalid: invalid == .new)
                        BRSecureField(
                            label: Copy.Passphrase.confirm, text: $confirmation, contentType: .newPassword,
                            invalid: invalid == .confirm)
                        if let message { ProblemLine(text: message) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(Copy.Passphrase.save, action: save)
                    .buttonStyle(.brPrimary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }
            .background(Palette.paper)
            .navigationTitle(isChange ? Copy.Passphrase.changeTitle : Copy.Passphrase.setTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FlowTitle(text: isChange ? Copy.Passphrase.changeTitle : Copy.Passphrase.setTitle)
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Passphrase.cancel) { dismiss() }.brFont(.navAction)
                }
            }
        }
        .tint(Palette.accent)
        #if DEBUG
            .task {
                // Simulator-only: `-debugPassphraseError` fills the fields so the two new ones don't match.
                guard CommandLine.arguments.contains("-debugPassphraseError") else { return }
                current = backup.passphrases.stored() ?? ""
                entry = "new passphrase"
                confirmation = "new passphras"
                try? await Task.sleep(for: .milliseconds(600))
                save()
            }
        #endif
    }

    private func fail(_ field: Field, _ text: String) {
        invalid = field
        message = text
    }

    private func save() {
        invalid = nil
        message = nil
        if isChange, !backup.isCurrentPassphrase(current) {
            fail(.current, Copy.Passphrase.wrongCurrent)
        } else if !PassphraseStore.isAcceptable(entry) {
            fail(.new, Copy.Passphrase.tooShort)
        } else if entry != confirmation {
            fail(.confirm, Copy.Passphrase.mismatch)
        } else {
            do {
                try backup.savePassphrase(entry)
                dismiss()
            } catch {
                message = Copy.Passphrase.saveFailed
            }
        }
    }
}
