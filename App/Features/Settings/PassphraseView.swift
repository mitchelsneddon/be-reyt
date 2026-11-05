import SwiftUI

/// Set or change the backup passphrase: the only rule is 8 characters. Changing asks for the current one.
struct PassphraseView: View {
    let backup: BackupSettingsModel
    let isChange: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var entry = ""
    @State private var confirmation = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Copy.Passphrase.warning).font(.body).foregroundStyle(Color("ink"))
                }
                Section {
                    if isChange {
                        SecureField(Copy.Passphrase.current, text: $current)
                            .textContentType(.password)
                            .frame(minHeight: 44)
                    }
                    SecureField(Copy.Passphrase.new, text: $entry)
                        .textContentType(.newPassword)
                        .frame(minHeight: 44)
                    SecureField(Copy.Passphrase.confirm, text: $confirmation)
                        .textContentType(.newPassword)
                        .frame(minHeight: 44)
                } footer: {
                    if let message { Text(message).foregroundStyle(Color("ink")) }
                }
                Section {
                    Button(Copy.Passphrase.save, action: save).frame(minHeight: 44)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("paper"))
            .navigationTitle(isChange ? Copy.Passphrase.changeTitle : Copy.Passphrase.setTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Passphrase.cancel) { dismiss() }
                }
            }
        }
        .tint(Color("accent"))
    }

    private func save() {
        if isChange, !backup.isCurrentPassphrase(current) {
            message = Copy.Passphrase.wrongCurrent
        } else if !PassphraseStore.isAcceptable(entry) {
            message = Copy.Passphrase.tooShort
        } else if entry != confirmation {
            message = Copy.Passphrase.mismatch
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
