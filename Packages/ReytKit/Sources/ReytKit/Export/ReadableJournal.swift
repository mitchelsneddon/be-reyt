import Foundation

/// One day of the journal, assembled for a readable export (Markdown or PDF). Plain values: no Markdown, no
/// layout. Both renderers read this, so the two formats can never disagree about what a day contains.
public struct ReadableDay: Sendable, Equatable {
    public struct Answer: Sendable, Equatable {
        public var title: String
        public var body: String
    }

    public struct Plan: Sendable, Equatable {
        public var text: String
        public var categoryLabel: String?
    }

    public struct FollowUp: Sendable, Equatable {
        /// What was planned, when that plan is still around.
        public var plan: String?
        public var note: String
    }

    public struct Photo: Sendable, Equatable {
        public var id: UUID
        /// Path under the generation's attachments directory.
        public var relativePath: String
        /// File name inside an export's `photos/` folder.
        public var fileName: String
    }

    public var key: DateKey
    public var heading: String
    public var scoreLabel: String?
    public var moods: [String]
    public var tags: [String]
    public var text: String?
    public var answers: [Answer]
    public var plan: Plan?
    public var followUp: FollowUp?
    public var photos: [Photo]
    public var workouts: [String]
}

/// A week's "more of this" note from the reviews screen.
public struct ReadableWeek: Sendable, Equatable {
    public var weekStart: DateKey
    public var weekEnd: DateKey
    public var moreOfThis: String
}

public struct ReadableJournal: Sendable, Equatable {
    public var days: [ReadableDay]
    public var weeks: [ReadableWeek]
    public var includeWorkouts: Bool
}

public enum ReadableFormat {
    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
        "december",
    ]

    public static let smileQuestion = "what made me smile today?"
    public static let reflectionTitle = "reflection"
    public static let followUpTitle = "how did that go?"
    public static let planTitle = "plan for the week"

    /// "thursday, 5 november 2026". Built from the civil day with fixed English names, so it is the same on every
    /// device and in every locale.
    public static func longDate(_ key: DateKey) -> String {
        "\(weekdays[key.weekday]), \(key.day) \(months[key.month - 1]) \(key.year)"
    }

    /// "5 november 2026".
    public static func shortDate(_ key: DateKey) -> String { "\(key.day) \(months[key.month - 1]) \(key.year)" }

    /// "november 2026".
    public static func monthTitle(year: Int, month: Int) -> String { "\(months[month - 1]) \(year)" }

    /// "1 h 16 min", "45 min", "2 h".
    static func duration(seconds: Double) -> String {
        let total = Int((seconds / 60).rounded())
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 { return "\(max(minutes, 1)) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    static func decimal(_ value: Double, places: Int) -> String {
        let factor = pow(10.0, Double(places))
        let rounded = (value * factor).rounded() / factor
        if places == 0 || rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.\(places)f", rounded)
    }

    static func workoutLine(_ w: WorkoutSnapshotValue) -> String {
        let activity = WorkoutActivity(id: w.activityType)
        var parts = [activity.displayName, duration(seconds: w.durationSeconds)]
        if let meters = w.distanceMeters, meters > 0 {
            parts.append(
                activity == .swimming ? "\(decimal(meters, places: 0)) m" : "\(decimal(meters / 1000, places: 1)) km")
        }
        if let kcal = w.energyKcal, kcal > 0 { parts.append("\(decimal(kcal, places: 0)) kcal") }
        return parts.joined(separator: ", ")
    }

    public static func nonblank(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}

extension ReadableJournal {
    /// Builds the readable view of the journal. A day appears only when it has user content (the same rule as
    /// `DayContent.hasUserContent`): a day with only a prompt assignment or only workouts is left out. `range`
    /// limits the days (inclusive). Workouts are read only when `includeWorkouts`.
    public init(_ data: ArchiveData, includeWorkouts: Bool, range: ClosedRange<DateKey>? = nil) {
        func inRange(_ key: DateKey) -> Bool { range?.contains(key) ?? true }

        let tagNames = Dictionary(data.tags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let entries = Dictionary(
            data.entries.compactMap { e in DateKey(e.dateKey).map { ($0, e) } }, uniquingKeysWith: { first, _ in first }
        )
        let prompts = Dictionary(
            data.promptAssignments.compactMap { p in DateKey(p.dateKey).map { ($0, p) } },
            uniquingKeysWith: { first, _ in first })
        var photos: [DateKey: [AttachmentDTO]] = [:]
        for a in data.attachments {
            if let key = DateKey(a.entryDateKey) { photos[key, default: []].append(a) }
        }
        var plans: [DateKey: WeeklyIntentionDTO] = [:]
        var followUps: [DateKey: [WeeklyIntentionDTO]] = [:]
        for i in data.intentions {
            if let sunday = DateKey(i.sourceSundayKey),
                ReadableFormat.nonblank(i.text) != nil || ReadableFormat.nonblank(i.category) != nil
            {
                plans[sunday] = i
            }
            if let written = DateKey(i.followUpWrittenOnKey ?? ""), ReadableFormat.nonblank(i.followUpNote) != nil {
                followUps[written, default: []].append(i)
            }
        }
        var workoutsByDay: [DateKey: [WorkoutSnapshotValue]] = [:]
        if includeWorkouts {
            for w in data.workouts {
                if let key = DateKey(w.dateKey) {
                    workoutsByDay[key, default: []].append(
                        WorkoutSnapshotValue(
                            healthKitUUID: w.healthKitUUID, sourceName: w.sourceName, activityType: w.activityType,
                            start: w.start, end: w.end, durationSeconds: w.durationSeconds,
                            distanceMeters: w.distanceMeters, energyKcal: w.energyKcal))
                }
            }
        }

        var keys = Set(entries.keys)
        keys.formUnion(photos.keys)
        keys.formUnion(plans.keys)
        keys.formUnion(followUps.keys)

        var days: [ReadableDay] = []
        for key in keys.sorted() where inRange(key) {
            let entry = entries[key]
            let text = ReadableFormat.nonblank(entry?.text)
            let smile = ReadableFormat.nonblank(entry?.smileAnswer)
            let rotating = ReadableFormat.nonblank(entry?.rotatingAnswer)
            let score = entry?.dayScore.flatMap { DayScore(rawValue: $0) }?.label
            let moods = MoodCatalog.normalize(entry?.moodIDs ?? []).map { MoodCatalog.label(for: $0) ?? $0 }
            let tags = (entry?.tagIDs ?? []).compactMap { tagNames[$0] }.filter { !$0.isEmpty }
            let dayPhotos = (photos[key] ?? [])
                .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
                .compactMap { a -> ReadableDay.Photo? in
                    let ext = (a.relativePath as NSString).pathExtension
                    guard ArchiveNames.isSafeExtension(ext) else { return nil }
                    return ReadableDay.Photo(
                        id: a.id, relativePath: a.relativePath,
                        fileName: ArchiveNames.attachmentFileName(id: a.id, ext: ext))
                }
            let plan = plans[key].map {
                ReadableDay.Plan(
                    text: $0.text,
                    categoryLabel: ReadableFormat.nonblank($0.category).map {
                        $0.replacingOccurrences(of: "-", with: " ")
                    })
            }
            let followUp = followUps[key]?.sorted { $0.sourceSundayKey < $1.sourceSundayKey }.first.flatMap { i in
                ReadableFormat.nonblank(i.followUpNote).map {
                    ReadableDay.FollowUp(plan: ReadableFormat.nonblank(i.text), note: $0)
                }
            }
            var answers: [ReadableDay.Answer] = []
            if let smile { answers.append(.init(title: ReadableFormat.smileQuestion, body: smile)) }
            if let rotating {
                answers.append(
                    .init(
                        title: ReadableFormat.nonblank(prompts[key]?.promptText) ?? ReadableFormat.reflectionTitle,
                        body: rotating))
            }
            let workouts = WorkoutDedupe.collapse(workoutsByDay[key] ?? []).map {
                ReadableFormat.workoutLine($0.representative)
            }

            let hasContent =
                text != nil || !answers.isEmpty || score != nil || !moods.isEmpty || !tags.isEmpty
                || !dayPhotos.isEmpty || plan != nil || followUp != nil
            guard hasContent else { continue }
            days.append(
                ReadableDay(
                    key: key, heading: ReadableFormat.longDate(key), scoreLabel: score, moods: moods, tags: tags,
                    text: text, answers: answers, plan: plan, followUp: followUp, photos: dayPhotos,
                    workouts: workouts))
        }

        var weeks: [ReadableWeek] = []
        for r in data.reviews {
            guard let note = ReadableFormat.nonblank(r.moreOfThisText), let start = DateKey(r.weekStartKey),
                let end = DateKey(r.weekEndKey), inRange(start) || inRange(end)
            else { continue }
            weeks.append(ReadableWeek(weekStart: start, weekEnd: end, moreOfThis: note))
        }
        weeks.sort { $0.weekStart < $1.weekStart }

        self.init(days: days, weeks: weeks, includeWorkouts: includeWorkouts)
    }
}
