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
    @State private var health: HealthCoordinator
    @State private var reminders: ReminderScheduler
    @State private var journalImporter: AppleJournalImporter
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let host = ContainerHost()
        let events = JournalEvents()
        _host = State(initialValue: host)
        _events = State(initialValue: events)
        _backup = State(initialValue: BackupSettingsModel(host: host))
        let restore = RestoreCoordinator(host: host, events: events)
        let health = HealthCoordinator(host: host, events: events)
        let reminders = ReminderScheduler(host: host, events: events)
        restore.registerPostRestoreHook { await health.resyncAfterRestore() }
        restore.registerPostRestoreHook { await reminders.refresh() }
        events.onContentChange = { days in Task { await reminders.contentChanged(days: days) } }
        _reminders = State(initialValue: reminders)
        _journalImporter = State(initialValue: AppleJournalImporter(host: host, events: events))
        _restore = State(initialValue: restore)
        _health = State(initialValue: health)
    }

    var body: some Scene {
        WindowGroup {
            content
                #if DEBUG
                    .task { await DebugBackup.runIfRequested(host: host, restore: restore) }
                    .task { await DebugReadableExport.runIfRequested(host: host) }
                    .task { await DebugImport.runIfRequested(host: host, importer: journalImporter) }
                #endif
                .overlay { if scenePhase != .active { PrivacyCover() } }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        host.openIfPossible()
                        lock.didBecomeActive()
                        Task { await health.syncIfDue() }
                        Task { await reminders.refresh() }
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
            .environment(health)
            .environment(reminders)
            .environment(journalImporter)
            .appleJournalImportSheet(journalImporter)
            .task { await health.syncIfDue() }
            .task {
                #if DEBUG
                    if CommandLine.arguments.contains("-autoEnableReminders") {
                        await reminders.requestAuthorizationIfNeeded()
                    }
                #endif
                await reminders.refresh()
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    await reminders.refresh()
                }
            }
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
