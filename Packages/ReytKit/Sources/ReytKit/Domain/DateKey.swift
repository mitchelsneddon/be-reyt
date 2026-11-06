import Foundation

/// A civil calendar day (proleptic Gregorian), stored as "YYYY-MM-DD".
/// With `WeekCalendar`, this is the only place that converts `Date` to and from a civil day (A4).
public struct DateKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Failable: rejects anything that is not a real calendar date.
    public init?(year: Int, month: Int, day: Int) {
        guard (0...9999).contains(year), (1...12).contains(month), day >= 1,
            day <= DateKey.daysInMonth(year: year, month: month)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly "YYYY-MM-DD".
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The civil day of `date` in the calendar's time zone.
    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // Calendar always returns valid components for a real Date; fall back to the epoch only if it does not.
        self = DateKey(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1) ?? DateKey(epochDay: 0)
    }

    /// Inverse of `epochDay` (Howard Hinnant's civil_from_days).
    public init(epochDay: Int) {
        let z = epochDay + 719_468
        let era = DateKey.floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.year = y
        self.month = m
        self.day = d
    }

    public var string: String {
        let y = String(year)
        return String(repeating: "0", count: max(0, 4 - y.count)) + y
            + "-" + (month < 10 ? "0" : "") + String(month)
            + "-" + (day < 10 ? "0" : "") + String(day)
    }

    public var description: String { string }

    /// Days since 1970-01-01 (negative before). Pure integer arithmetic, so DST cannot affect it.
    public var epochDay: Int {
        let y = month <= 2 ? year - 1 : year
        let era = DateKey.floorDiv(y, 400)
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// 0 = Sunday ... 6 = Saturday. 1970-01-01 was a Thursday.
    public var weekday: Int { DateKey.floorMod(epochDay + 4, 7) }

    /// ISO 8601 week number (1...53): weeks start on Monday and week 1 holds the year's first Thursday.
    public var isoWeek: Int {
        let isoWeekday = weekday == 0 ? 7 : weekday
        let thursday = adding(days: 4 - isoWeekday)
        guard let firstOfYear = DateKey(year: thursday.year, month: 1, day: 1) else { return 1 }
        return thursday.days(from: firstOfYear) / 7 + 1
    }

    public func adding(days: Int) -> DateKey { DateKey(epochDay: epochDay + days) }

    /// Whole days from `other` to self (self - other).
    public func days(from other: DateKey) -> Int { epochDay - other.epochDay }

    /// Start of this civil day in the calendar's time zone.
    public func date(in calendar: Calendar) -> Date {
        // Build at noon then take startOfDay, so a day whose midnight does not exist (some zones) still resolves.
        let noon = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let d = calendar.date(from: noon) else { return Date(timeIntervalSince1970: 0) }
        return calendar.startOfDay(for: d)
    }

    public static func < (lhs: DateKey, rhs: DateKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DateKey(s) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "not a YYYY-MM-DD date"))
        }
        self = k
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    private static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    private static func floorMod(_ a: Int, _ b: Int) -> Int { a - floorDiv(a, b) * b }
}
