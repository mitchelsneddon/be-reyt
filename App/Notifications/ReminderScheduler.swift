import Foundation
import Observation
import ReytKit
import UIKit
import UserNotifications

/// Keeps a bounded run of date-specific local notification requests in step with the journal. Nothing relies on
/// code running at 9 pm: the next 28 days are scheduled ahead and topped up whenever the app is used. The
/// decision of which days get one is `ReminderPlan` (pure, tested); this only talks to the system.
@MainActor @Observable
final class ReminderScheduler {
    enum Permission: Equatable { case unknown, notDetermined, denied, allowed }

    private(set) var settings = ReminderSettings(enabled: true, hour: 21)
    private(set) var permission: Permission = .unknown

    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let events: JournalEvents
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var tail: Task<Void, Never>?

    static let threadID = "reminder"

    init(host: ContainerHost, events: JournalEvents) {
        self.host = host
        self.events = events
    }

    // MARK: Triggers

    /// Launch, foreground, midnight, settings changes and restore all land here. Safe to call as often as needed.
    func refresh() async {
        await serialized { await self.reconcile() }
    }

    /// `JournalEvents` hook. Today flipping (content added or all removed) reconciles at once; a future day inside
    /// the window reconciles too; a past day never touches anything.
    func contentChanged(days: Set<DateKey>) async {
        let today = AppClock.today()
        guard days.contains(where: { $0 >= today }) else { return }
        await refresh()
    }

    func setEnabled(_ enabled: Bool) async {
        await write(enabled: enabled, hour: settings.hour)
        if enabled { await requestAuthorizationIfNeeded() }
    }

    func setHour(_ hour: Int) async {
        await write(enabled: settings.enabled, hour: hour)
    }

    /// Shows the system sheet the first time only; afterwards it just re-reads the status.
    func requestAuthorizationIfNeeded() async {
        await readPermission()
        if permission == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await readPermission()
        }
        await refresh()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Work

    private func write(enabled: Bool, hour: Int) async {
        guard let store = host.store else { return }
        if let effect = try? await store.updateReminderSettings(enabled: enabled, hour: hour) {
            events.receive(effect)
        }
        await refresh()
    }

    private func readPermission() async {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: permission = .notDetermined
        case .denied: permission = .denied
        default: permission = .allowed
        }
    }

    /// Runs operations one after another, so a refresh never interleaves with another and re-adds a removed day.
    private func serialized(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
        await task.value
    }

    private func reconcile() async {
        guard let store = host.store else { return }
        await readPermission()
        guard let current = try? await store.reminderSettings() else { return }
        settings = current

        let calendar = Calendar.current
        let now = AppClock.now()
        let today = DateKey(date: now, calendar: calendar)
        let horizon = ReminderPlan.defaultHorizonDays
        let window = try? await store.contentDays(from: today, through: today.adding(days: horizon - 1))
        guard let contentDays = window else { return }

        // Content written today also retires a reminder that has already been delivered.
        if contentDays.contains(today) {
            center.removeDeliveredNotifications(withIdentifiers: [ReminderPlan.identifier(for: today)])
        }

        let desired = ReminderPlan.dates(
            today: today, now: now, calendar: calendar, hour: current.hour, horizonDays: horizon,
            contentDays: contentDays, enabled: current.enabled)
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let changes = ReminderPlan.diff(pending: pendingIDs, desired: desired)

        center.removePendingNotificationRequests(withIdentifiers: changes.remove)
        // A changed hour keeps the same identifiers, so re-add any whose trigger no longer matches.
        let stale = pending.filter { request in
            guard let key = ReminderPlan.parse(identifier: request.identifier),
                let trigger = request.trigger as? UNCalendarNotificationTrigger
            else { return false }
            return desired.contains(key) && trigger.dateComponents.hour != current.hour
        }
        for key in changes.add + stale.compactMap({ ReminderPlan.parse(identifier: $0.identifier) }) {
            try? await center.add(request(for: key, hour: current.hour))
        }
        #if DEBUG
            await Self.dumpIfRequested(center: center)
        #endif
    }

    private func request(for day: DateKey, hour: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = Copy.Reminder.notificationTitle
        content.body = Copy.Reminder.notificationBody
        content.sound = .default
        content.threadIdentifier = Self.threadID
        // No time zone on the components, so the request follows the phone's local time wherever it travels.
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: 0)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: ReminderPlan.identifier(for: day), content: content, trigger: trigger)
    }

    #if DEBUG
        /// `-dumpReminders`: writes `Documents/reminders.json` with pending reminder identifiers and their trigger
        /// components. Identifiers and dates only, never content.
        private static func dumpIfRequested(center: UNUserNotificationCenter) async {
            guard CommandLine.arguments.contains("-dumpReminders") else { return }
            let pending = await center.pendingNotificationRequests()
            let rows: [[String: Any]] = pending.compactMap { request in
                guard request.identifier.hasPrefix(ReminderPlan.identifierPrefix) else { return nil }
                var row: [String: Any] = ["id": request.identifier]
                if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                    let c = trigger.dateComponents
                    row["year"] = c.year
                    row["month"] = c.month
                    row["day"] = c.day
                    row["hour"] = c.hour
                    row["minute"] = c.minute
                    row["repeats"] = trigger.repeats
                }
                return row
            }.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
            let report: [String: Any] = ["count": rows.count, "pending": rows]
            guard
                let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
                let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            else { return }
            try? data.write(
                to: documents.appending(path: "reminders.json", directoryHint: .notDirectory), options: .atomic)
        }
    #endif
}
