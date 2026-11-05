import Foundation

/// A Sunday "one thing for next week" plan as plain values, with its optional follow-up.
public struct IntentionPlan: Sendable, Equatable, Identifiable {
    public var sourceSunday: DateKey
    public var targetStart: DateKey
    public var targetEnd: DateKey
    public var text: String
    public var category: String?
    public var followUpNote: String?
    public var followUpWrittenOn: DateKey?
    public var followUpSkipped: Bool

    public var id: DateKey { sourceSunday }

    public init(
        sourceSunday: DateKey, targetStart: DateKey, targetEnd: DateKey, text: String, category: String? = nil,
        followUpNote: String? = nil, followUpWrittenOn: DateKey? = nil, followUpSkipped: Bool = false
    ) {
        self.sourceSunday = sourceSunday
        self.targetStart = targetStart
        self.targetEnd = targetEnd
        self.text = text
        self.category = category
        self.followUpNote = followUpNote
        self.followUpWrittenOn = followUpWrittenOn
        self.followUpSkipped = followUpSkipped
    }

    /// A plan with nothing to show (kept as a row only because it carries a follow-up).
    public var isBlank: Bool { !DayContent.isNonblank(text) && !DayContent.isNonblank(category) }

    /// True once the follow-up has a note or has been skipped.
    public var hasFollowUpResponse: Bool { DayContent.isNonblank(followUpNote) || followUpSkipped }
}

/// Pure lookups over already-fetched plans. Fetching stays in `JournalStore`.
public enum IntentionQueries {
    /// The plan whose target week (Monday to Sunday) contains `day`.
    public static func planCovering(day: DateKey, in plans: [IntentionPlan]) -> IntentionPlan? {
        plans.first { !$0.isBlank && day >= $0.targetStart && day <= $0.targetEnd }
    }

    /// The plan whose follow-up belongs on `day`: the Sunday that ends its target week.
    public static func followUpDue(on day: DateKey, in plans: [IntentionPlan]) -> IntentionPlan? {
        plans.first { !$0.isBlank && $0.targetEnd == day }
    }

    /// The plan written on `sunday`, if any.
    public static func plan(sourcedOn sunday: DateKey, in plans: [IntentionPlan]) -> IntentionPlan? {
        plans.first { $0.sourceSunday == sunday }
    }
}
