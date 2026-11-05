import ReytKit
import SwiftData
import SwiftUI

@main
struct BeReytApp: App {
    @State private var host: ContainerHost
    @State private var events: JournalEvents
    @State private var lock = AppLock()
    @State private var backup: BackupSettingsModel
    @State private var restore: RestoreCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let host = ContainerHost()
        let events = JournalEvents()
        _host = State(initialValue: host)
        _events = State(initialValue: events)
        _backup = State(initialValue: BackupSettingsModel(host: host))
        _restore = State(initialValue: RestoreCoordinator(host: host, events: events))
    }

    var body: some Scene {
        WindowGroup {
            content
                #if DEBUG
                    .task { await DebugBackup.runIfRequested(host: host, restore: restore) }
                #endif
                .overlay { if scenePhase != .active { PrivacyCover() } }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        host.openIfPossible()
                        lock.didBecomeActive()
                    case .background:
                        lock.didEnterBackground()
                        host.protect()
                    default: break
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if let store = host.store, let attachments = host.attachments, let container = host.container,
            let generation = host.generationID
        {
            switch lock.state {
            case .unlocked:
                root(store: store, attachments: attachments, container: container, generation: generation)
            case .unavailable:
                root(store: store, attachments: attachments, container: container, generation: generation)
                    .safeAreaInset(edge: .top, spacing: 0) { NoPasscodeBanner() }
            case .locked, .authenticating:
                LockScreenView(lock: lock)
            }
        } else {
            WaitingView(failed: host.openFailed)
        }
    }
}

extension BeReytApp {
    fileprivate func root(
        store: JournalStore, attachments: AttachmentStore, container: ModelContainer, generation: String
    ) -> some View {
        RootView(store: store, events: events, attachments: attachments, backup: backup, restore: restore)
            .modelContainer(container)
            .id(generation)
    }
}

/// Shown until the container exists: the phone is still locked, or the store could not be opened.
private struct WaitingView: View {
    let failed: Bool

    var body: some View {
        Text(failed ? Copy.Host.openFailed : Copy.Host.unlockPhone)
            .font(.body)
            .foregroundStyle(Color("inkSecondary"))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("paper"))
    }
}
