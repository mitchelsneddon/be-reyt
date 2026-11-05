import Foundation
import Observation
import ReytKit

/// Main-actor face of `WorkoutSync`: decides when to sync, throttles it, forwards store effects to
/// `JournalEvents`, and tells Settings what to say about access.
@MainActor @Observable
final class HealthCoordinator {
    enum Access: Equatable { case unknown, unavailable, notAsked, asked }

    private(set) var access: Access = .unknown
    /// True once a sync has completed in this run, so Settings can tell "nothing yet" from "nothing found".
    private(set) var hasSynced = false

    /// Minimum gap between automatic syncs.
    static let throttle: Duration = .seconds(60)

    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let sync: WorkoutSync
    @ObservationIgnored private var lastRun: ContinuousClock.Instant?
    @ObservationIgnored private var isSyncing = false

    init(host: ContainerHost, events: JournalEvents) {
        self.host = host
        self.events = events
        sync = WorkoutSync(anchors: HealthAnchorStore(deviceRoot: host.paths.deviceRoot))
    }

    func refreshAccess() async {
        switch await sync.access() {
        case .unavailable: access = .unavailable
        case .notAsked: access = .notAsked
        case .asked: access = .asked
        }
    }

    /// Shows the system sheet (first time only; later calls return at once) and syncs.
    func requestAccess() async {
        try? await sync.requestAuthorization()
        await refreshAccess()
        await syncIfDue(force: true)
    }

    /// Launch, foreground and day-page appearance all call this; more than once a minute does nothing.
    func syncIfDue(force: Bool = false) async {
        guard !isSyncing, let store = host.store else { return }
        let now = ContinuousClock.now
        if !force, let lastRun, now - lastRun < Self.throttle { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let outcome = try await sync.sync(into: store)
            lastRun = now
            apply(outcome)
        } catch {
            // Not retried until the next trigger: the anchor did not move, so nothing is lost.
        }
        await refreshAccess()
    }

    /// Post-restore hook: anchor reset, full re-sync, drop what Health no longer has.
    func resyncAfterRestore() async {
        while isSyncing { try? await Task.sleep(for: .milliseconds(100)) }
        guard let store = host.store else { return }
        isSyncing = true
        defer { isSyncing = false }
        if let outcome = try? await sync.resyncAfterRestore(into: store) {
            lastRun = .now
            apply(outcome)
        }
        await refreshAccess()
    }

    private func apply(_ outcome: WorkoutSync.Outcome) {
        guard case .synced(let effect, _) = outcome else { return }
        hasSynced = true
        events.receive(effect)
    }
}
