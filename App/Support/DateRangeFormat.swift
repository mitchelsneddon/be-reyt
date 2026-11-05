import Foundation
import ReytKit

/// Lowercase day ranges built from `DateKey`s: "9–15 nov", "30 nov – 6 dec". The year is added when the range
/// is not in the same year as `today`, so an old plan stays unambiguous.
enum DateRangeFormat {
    static func string(from start: DateKey, to end: DateKey, today: DateKey, calendar: Calendar = .current) -> String {
        func month(_ key: DateKey) -> String {
            key.date(in: calendar).formatted(
                Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated)
            ).lowercased()
        }
        let startMonth = month(start)
        let endMonth = month(end)
        var text =
            start.month == end.month && start.year == end.year
            ? "\(start.day)–\(end.day) \(endMonth)"
            : "\(start.day) \(startMonth) – \(end.day) \(endMonth)"
        if end.year != today.year { text += " \(end.year)" }
        return text
    }
}
