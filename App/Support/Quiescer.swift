import Foundation
import ReytKit

/// The one quiesce/resume used by restore and delete-all, so both stop the same writers in the same order:
/// 1. pending drafts are written, 2. in-flight photo imports settle, 3. health sync finishes and stays suspended,
/// 4. automatic backups stop and stay suspended, 5. the store goes read-only.
/// `resume` reverses it. Restore re-enables backups through `didRestore` and delete-all through `forgetEverything`;
/// both also clear the suspension, so a successful swap never leaves a writer off.
@MainActor
final class Quiescer {
    private let events: JournalEvents
    private let backup: BackupManager
    private let health: HealthCoordinator

    init(events: JournalEvents, backup: BackupManager, health: HealthCoordinator) {
        self.events = events
        self.backup = backup
        self.health = health
    }

    func quiesce(store: JournalStore, attachments: AttachmentStore) async {
        await events.flushAllDrafts()
        await attachments.waitForIdle()
        await health.suspendAndSettle()
        await backup.suspend()
        await store.setReadOnly(true)
    }

    /// Undoes `quiesce`. `reopenStore` is false when the pointer already names a different generation, so the old
    /// store stays read-only.
    func resume(store: JournalStore, reopenStore: Bool) async {
        if reopenStore { await store.setReadOnly(false) }
        health.resume()
        backup.resumeAfterQuiesce()
    }

    /// After a delete-all swap: the new empty journal is live and the device wipers have run.
    func resumeAfterWipe() {
        health.resume()
        backup.resumeAfterQuiesce()
    }
}
