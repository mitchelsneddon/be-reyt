import SwiftUI

/// The settings row, at the bottom of the list.
struct DeleteAllSection: View {
    var body: some View {
        Section {
            NavigationLink {
                DeleteAllView()
            } label: {
                SettingsRowLabel(title: Copy.DeleteAll.row, icon: "trash", tint: .danger)
            }
            .accessibilityHint(Copy.DeleteAll.rowHint)
        }
        .settingsRows()
    }
}

/// Says exactly what goes and what stays, then asks for Face ID or the passcode and the word "delete".
struct DeleteAllView: View {
    @Environment(DeleteAllCoordinator.self) private var coordinator

    @State private var authenticated = Self.startsAuthenticated
    @State private var authMessage: String?
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private static let removeIcons = ["book.closed", "number", "key", "bell"]
    private static let keepIcons = ["folder", "heart"]

    private static var startsAuthenticated: Bool {
        #if DEBUG
            // Simulator-only: `-openDeleteAllConfirm` starts past the Face ID step.
            return CommandLine.arguments.contains("-openDeleteAllConfirm")
        #else
            return false
        #endif
    }

    private var isWorking: Bool { coordinator.phase == .working }

    var body: some View {
        List {
            Section {
                ForEach(Array(zip(Self.removeIcons, Copy.DeleteAll.removes)), id: \.1) { icon, text in
                    itemRow(icon: icon, text: text)
                }
            } header: {
                SettingsHeader(Copy.DeleteAll.removesHeader)
            }
            .settingsRows()
            Section {
                ForEach(Array(zip(Self.keepIcons, Copy.DeleteAll.keeps)), id: \.1) { icon, text in
                    itemRow(icon: icon, text: text)
                }
            } header: {
                SettingsHeader(Copy.DeleteAll.keepsHeader)
            }
            .settingsRows()
            Section {
                Text(Copy.DeleteAll.irreversible)
                    .brFont(.rowWrapping).foregroundStyle(Palette.danger)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
            }
            if !authenticated {
                Section {
                    Button(Copy.DeleteAll.continueAction) { authenticate() }
                        .buttonStyle(.brDestructive)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                } footer: {
                    if let authMessage { problem(authMessage) }
                }
            } else {
                Section {
                    TextField(Copy.DeleteAll.confirmField, text: $typed)
                        .brFont(.row)
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .disabled(isWorking)
                        .frame(minHeight: 52)
                        .accessibilityLabel(Copy.DeleteAll.confirmField)
                }
                .settingsRows()
                Section {
                    Button {
                        Task { await coordinator.deleteAll() }
                    } label: {
                        Text(Copy.DeleteAll.action)
                    }
                    .buttonStyle(.brDestructiveFilled)
                    .disabled(typed != Copy.DeleteAll.confirmWord || isWorking)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                } footer: {
                    if isWorking {
                        HStack(spacing: 10) {
                            ProgressRing(size: 18, lineWidth: 2.5)
                            Text(Copy.DeleteAll.working).brFont(.rowWrapping).foregroundStyle(Palette.ink2)
                        }
                        .accessibilityElement(children: .combine)
                    } else if coordinator.phase == .failed {
                        problem(Copy.DeleteAll.failed)
                    }
                }
            }
        }
        .listSectionSpacing(20)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .tint(Palette.accent)
        .navigationTitle(Copy.DeleteAll.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            coordinator.resetFailure()
        }
    }

    private func itemRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Palette.ink2)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text).brFont(.rowWrapping).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 13)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private func problem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").accessibilityLabel(Copy.Settings.problem)
            Text(text)
        }
        .brFont(.rowWrapping).foregroundStyle(Palette.danger)
        .accessibilityElement(children: .combine)
    }

    private func authenticate() {
        Task {
            if await Reauthenticator.confirm(reason: Copy.DeleteAll.reauthReason) {
                authenticated = true
                authMessage = nil
                fieldFocused = true
            } else {
                authMessage = Copy.DeleteAll.reauthFailed
            }
        }
    }
}
