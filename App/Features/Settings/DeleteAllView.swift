import SwiftUI

/// The settings row, at the bottom of the list.
struct DeleteAllSection: View {
    var body: some View {
        Section {
            NavigationLink {
                DeleteAllView()
            } label: {
                Text(Copy.DeleteAll.row).foregroundStyle(.red)
            }
            .accessibilityHint(Copy.DeleteAll.rowHint)
            .frame(minHeight: 44)
        }
    }
}

/// Says exactly what goes and what stays, then asks for Face ID or the passcode and the word "delete".
struct DeleteAllView: View {
    @Environment(DeleteAllCoordinator.self) private var coordinator

    @State private var authenticated = false
    @State private var authMessage: String?
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var isWorking: Bool { coordinator.phase == .working }

    var body: some View {
        List {
            Section(Copy.DeleteAll.removesHeader) {
                ForEach(Copy.DeleteAll.removes, id: \.self) { Text($0) }
            }
            Section(Copy.DeleteAll.keepsHeader) {
                ForEach(Copy.DeleteAll.keeps, id: \.self) { Text($0) }
            }
            Section {
                Text(Copy.DeleteAll.irreversible).foregroundStyle(Color("ink"))
                if !authenticated {
                    Button(Copy.DeleteAll.continueAction) { authenticate() }.frame(minHeight: 44)
                } else {
                    TextField(Copy.DeleteAll.confirmField, text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .disabled(isWorking)
                        .frame(minHeight: 44)
                        .accessibilityLabel(Copy.DeleteAll.confirmPrompt)
                    Button(role: .destructive) {
                        Task { await coordinator.deleteAll() }
                    } label: {
                        HStack {
                            Text(Copy.DeleteAll.action)
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(typed != Copy.DeleteAll.confirmWord || isWorking)
                    .frame(minHeight: 44)
                }
            } footer: {
                if let message = footerMessage { Text(message).foregroundStyle(Color("ink")) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("paper"))
        .navigationTitle(Copy.DeleteAll.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { coordinator.resetFailure() }
    }

    private var footerMessage: String? {
        if isWorking { return Copy.DeleteAll.working }
        if coordinator.phase == .failed { return Copy.DeleteAll.failed }
        if authenticated { return Copy.DeleteAll.confirmPrompt }
        return authMessage
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

/// One calm line after delete-all rebuilt the app.
struct DeleteAllNoteBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.footnote).foregroundStyle(Color("ink"))
            Spacer()
            Button(Copy.DeleteAll.dismiss, action: dismiss).font(.footnote).frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .background(Color("paper"))
        .accessibilityElement(children: .contain)
    }
}
