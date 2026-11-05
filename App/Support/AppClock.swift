import Foundation
import ReytKit

/// The app's single notion of "now" and "today". DEBUG builds accept `-pretendToday YYYY-MM-DD` so the
/// Sunday and Monday flows can be exercised in the simulator; release builds always use the real clock.
enum AppClock {
    /// Injected into `JournalStore` and read by Today, so everything agrees on the day.
    static let now: @Sendable () -> Date = {
        #if DEBUG
            if let key = pretendedDay { return key.date(in: .current).addingTimeInterval(12 * 3600) }
        #endif
        return Date.now
    }

    static func today(calendar: Calendar = .current) -> DateKey {
        DateKey(date: now(), calendar: calendar)
    }

    #if DEBUG
        private static let pretendedDay: DateKey? = {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "-pretendToday"), args.indices.contains(i + 1) else { return nil }
            return DateKey(args[i + 1])
        }()
    #endif
}
