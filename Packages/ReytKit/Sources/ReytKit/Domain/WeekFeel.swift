import Foundation

/// A plain summary of how a review week felt, built only from `WeeklyStats` (no new statistics).
public struct WeekFeel: Sendable, Equatable {
    /// The week's overall feel, from the raw average score. Scores run 1 to 5. Thresholds (lower bound inclusive):
    /// difficult below 2.5, mixed 2.5 up to 3.0, okay 3.0 up to 3.5, good 3.5 up to 4.5, great 4.5 and above.
    public enum Band: Sendable, Equatable, CaseIterable {
        case difficult, mixed, okay, good, great

        public init(average: Double) {
            switch average {
            case ..<2.5: self = .difficult
            case ..<3.0: self = .mixed
            case ..<3.5: self = .okay
            case ..<4.5: self = .good
            default: self = .great
            }
        }
    }

    /// Versus last week. Taken from the existing `scoreComparison`, so its thin-data rule already applies. The
    /// shown averages differ by at least 0.3 for brighter or harder, otherwise similar.
    public enum Direction: Sendable, Equatable {
        case brighter, similar, harder

        /// Smallest difference between the displayed averages (in tenths) that counts as a change.
        public static let thresholdTenths = 3
    }

    public struct TopMood: Sendable, Equatable {
        public let id: String
        public let dayCount: Int
    }

    public let band: Band?
    public let topMood: TopMood?
    public let direction: Direction?

    /// Nil when no day is scored and no mood is logged.
    public static func make(from stats: WeeklyStats) -> WeekFeel? {
        let band = stats.averageScore.map(Band.init(average:))
        // `moodFrequency` is already in catalog order, so the first maximum wins ties.
        var top: TopMood?
        for m in stats.moodFrequency where m.dayCount > (top?.dayCount ?? 0) {
            top = TopMood(id: m.moodID, dayCount: m.dayCount)
        }
        guard band != nil || top != nil else { return nil }
        let direction = stats.scoreComparison.map { c -> Direction in
            if c.deltaTenths >= Direction.thresholdTenths { return .brighter }
            if c.deltaTenths <= -Direction.thresholdTenths { return .harder }
            return .similar
        }
        return WeekFeel(band: band, topMood: top, direction: direction)
    }
}
