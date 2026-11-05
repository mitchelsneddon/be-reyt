import Foundation

/// Which days should hold a pending reminder, and how to get from what is pending to that. Pure: the app's
/// `ReminderScheduler` does the `UserNotifications` calls. A day "has an entry" per `DayContent.hasUserContent` (A3).
public enum ReminderPlan {
    public static let identifierPrefix = "reminder-"
    public static let defaultHorizonDays = 28

    /// Days that should have a reminder: from `today` (only while `now` is before today's reminder time in
    /// `calendar`) through `today + horizonDays - 1`, minus days in `contentDays`. Empty when disabled.
    public static func dates(
        today: DateKey, now: Date, calendar: Calendar, hour: Int, horizonDays: Int = defaultHorizonDays,
        contentDays: Set<DateKey>, enabled: Bool
    ) -> [DateKey] {
        guard enabled, horizonDays > 0 else { return [] }
        let todayStillAhead = fireDate(today, hour: hour, calendar: calendar).map { now < $0 } ?? false
        return (0..<horizonDays)
            .map { today.adding(days: $0) }
            .filter { ($0 != today || todayStillAhead) && !contentDays.contains($0) }
    }

    /// The instant of `day`'s reminder in `calendar`, nil only if the calendar cannot build it.
    public static func fireDate(_ day: DateKey, hour: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: 0))
    }

    public static func identifier(for day: DateKey) -> String { identifierPrefix + day.string }

    public static func parse(identifier: String) -> DateKey? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return DateKey(String(identifier.dropFirst(identifierPrefix.count)))
    }

    /// What to add and what to remove so that the reminder identifiers pending equal those `desired` names.
    /// Identifiers without the "reminder-" prefix are never touched. A reminder-prefixed identifier that is
    /// pending but not desired (including a malformed one) is removed.
    public static func diff(pending: Set<String>, desired: [DateKey]) -> (add: [DateKey], remove: [String]) {
        let ours = pending.filter { $0.hasPrefix(identifierPrefix) }
        let wanted = Set(desired.map(identifier(for:)))
        let add = desired.filter { !ours.contains(identifier(for: $0)) }
        return (add, ours.subtracting(wanted).sorted())
    }
}
