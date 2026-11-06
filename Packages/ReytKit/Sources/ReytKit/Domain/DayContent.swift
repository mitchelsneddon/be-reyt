import Foundation

/// Everything that can make a day "have an entry", assembled from the entry, its attachments, the Sunday
/// intention sourced on that day and any follow-up note written on that day.
/// `hasUserContent` is the single definition used by reminders, coverage and history dots (A3).
/// A prompt assignment and workouts never count.
public struct DayContent: Sendable, Equatable {
    public var text: String
    public var smileAnswer: String?
    public var rotatingAnswer: String?
    public var dayScore: Int?
    public var moodIDs: [String]
    public var attachmentCount: Int
    /// A Sunday intention sourced on this day with nonblank text or a category.
    public var hasIntention: Bool
    /// A nonblank follow-up note written on this day.
    public var hasFollowUpNote: Bool

    public init(
        text: String = "", smileAnswer: String? = nil, rotatingAnswer: String? = nil, dayScore: Int? = nil,
        moodIDs: [String] = [], attachmentCount: Int = 0, hasIntention: Bool = false,
        hasFollowUpNote: Bool = false
    ) {
        self.text = text
        self.smileAnswer = smileAnswer
        self.rotatingAnswer = rotatingAnswer
        self.dayScore = dayScore
        self.moodIDs = moodIDs
        self.attachmentCount = attachmentCount
        self.hasIntention = hasIntention
        self.hasFollowUpNote = hasFollowUpNote
    }

    public var hasUserContent: Bool {
        Self.isNonblank(text) || Self.isNonblank(smileAnswer) || Self.isNonblank(rotatingAnswer)
            || dayScore != nil || !moodIDs.isEmpty || attachmentCount > 0 || hasIntention
            || hasFollowUpNote
    }

    static func isNonblank(_ s: String?) -> Bool {
        guard let s else { return false }
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
