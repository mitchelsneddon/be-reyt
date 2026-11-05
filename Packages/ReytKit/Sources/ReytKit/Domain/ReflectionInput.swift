import Foundation

/// Exactly what the reflection model reads for one review week, in canonical (sorted, deterministic) form.
/// Built by `JournalStore.reflectionInput(weekStart:)`; `ReviewFingerprint` hashes it, so anything the model
/// reads is covered by the fingerprint and nothing else is.
public struct ReflectionInput: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        public var dateKey: DateKey
        public var text: String
        public var smileAnswer: String?
        /// Wording of the rotating prompt, present only when it was answered (an unanswered prompt is not input).
        public var rotatingPrompt: String?
        public var rotatingAnswer: String?
        public var score: Int?
        public var moodIDs: [String]
        public var tagNames: [String]

        public init(
            dateKey: DateKey, text: String, smileAnswer: String?, rotatingPrompt: String?, rotatingAnswer: String?,
            score: Int?, moodIDs: [String], tagNames: [String]
        ) {
            self.dateKey = dateKey
            self.text = text
            self.smileAnswer = smileAnswer
            self.rotatingPrompt = rotatingPrompt
            self.rotatingAnswer = rotatingAnswer
            self.score = score
            self.moodIDs = moodIDs
            self.tagNames = tagNames
        }
    }

    public struct Intention: Codable, Sendable, Equatable {
        public var text: String
        public var category: String?
        public init(text: String, category: String?) {
            self.text = text
            self.category = category
        }
    }

    public struct FollowUp: Codable, Sendable, Equatable {
        public var writtenOn: DateKey
        public var note: String
        public init(writtenOn: DateKey, note: String) {
            self.writtenOn = writtenOn
            self.note = note
        }
    }

    public struct Workout: Codable, Sendable, Equatable {
        public var dateKey: DateKey
        public var activity: String
        public var durationSeconds: Double
        public var distanceMeters: Double?
        public init(dateKey: DateKey, activity: String, durationSeconds: Double, distanceMeters: Double?) {
            self.dateKey = dateKey
            self.activity = activity
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
        }
    }

    public var weekStart: DateKey
    public var days: [Day]
    public var intention: Intention?
    public var followUps: [FollowUp]
    public var workouts: [Workout]

    /// Sorts every collection so equal content always encodes identically.
    public init(
        weekStart: DateKey, days: [Day], intention: Intention?, followUps: [FollowUp], workouts: [Workout]
    ) {
        self.weekStart = weekStart
        self.days = days.sorted { $0.dateKey < $1.dateKey }.map { day in
            var d = day
            d.moodIDs = day.moodIDs.sorted()
            d.tagNames = day.tagNames.sorted()
            return d
        }
        self.intention = intention
        self.followUps = followUps.sorted { ($0.writtenOn, $0.note) < ($1.writtenOn, $1.note) }
        self.workouts = workouts.sorted {
            ($0.dateKey, $0.activity, $0.durationSeconds, $0.distanceMeters ?? -1)
                < ($1.dateKey, $1.activity, $1.durationSeconds, $1.distanceMeters ?? -1)
        }
    }
}
