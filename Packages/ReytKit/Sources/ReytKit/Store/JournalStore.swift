import Foundation
import SwiftData

public enum JournalStoreError: Error, Equatable, Sendable {
    case readOnly
    case promptAnswered
    case invalidTagName
    case tagNameTaken
    case notASunday
    case intentionNotFound
}

/// One change to a day's entry. Intent-level, so the store can detect no-ops and decide what to bump.
public enum EntryChange: Sendable, Equatable {
    case text(String)
    case smileAnswer(String?)
    case rotatingAnswer(String?)
    case score(DayScore?)
    case moods([String])
    case tags([UUID])
}

public struct PromptChoice: Sendable, Equatable {
    public var id: String
    public var text: String
    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct PromptHistoryItem: Sendable, Equatable {
    public var dateKey: DateKey
    public var promptID: String
    public init(dateKey: DateKey, promptID: String) {
        self.dateKey = dateKey
        self.promptID = promptID
    }
}

/// Supplied by the app (S5a's `PromptSelector`): picks a prompt for a day given the assignment history.
public typealias PromptSelection = @Sendable (DateKey, [PromptHistoryItem]) -> PromptChoice

/// Supplied by the app: picks the next prompt for a day given its current prompt ID and the assignment history.
public typealias PromptReroll = @Sendable (DateKey, String?, [PromptHistoryItem]) -> PromptChoice

/// A workout parsed at the HealthKit boundary (A6).
public struct AttachmentRef: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let relativePath: String
    public init(id: UUID, relativePath: String) {
        self.id = id
        self.relativePath = relativePath
    }
}

public struct WorkoutInput: Sendable, Equatable {
    public var healthKitUUID: UUID
    public var sourceName: String
    public var activityType: String
    public var start: Date
    public var end: Date
    public var dateKey: DateKey
    public var timeZoneID: String?
    public var durationSeconds: Double
    public var distanceMeters: Double?
    public var energyKcal: Double?

    public init(
        healthKitUUID: UUID, sourceName: String, activityType: String, start: Date, end: Date, dateKey: DateKey,
        timeZoneID: String? = nil, durationSeconds: Double, distanceMeters: Double? = nil, energyKcal: Double? = nil
    ) {
        self.healthKitUUID = healthKitUUID
        self.sourceName = sourceName
        self.activityType = activityType
        self.start = start
        self.end = end
        self.dateKey = dateKey
        self.timeZoneID = timeZoneID
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.energyKcal = energyKcal
    }
}

/// The only writer of journal records (A2). Every mutation returns a `StoreEffect`; a no-op returns an empty
/// effect and neither saves nor bumps. All inserts fetch first, so a unique key never gets a second row.
@ModelActor
public actor JournalStore {
    var clock: @Sendable () -> Date = { Date.now }
    var timeZone: TimeZone = .current
    private var readOnly = false
    /// Increments on every successful save. The archive writer compares it before and after copying attachments
    /// to detect a write that raced the snapshot.
    private(set) var writeCounter: UInt64 = 0

    public init(
        modelContainer: ModelContainer, clock: @escaping @Sendable () -> Date = { Date.now },
        timeZone: TimeZone = .current
    ) {
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.modelContainer = modelContainer
        self.clock = clock
        self.timeZone = timeZone
    }

    // MARK: Read-only mode

    /// While on, every mutation throws `JournalStoreError.readOnly` (restore swaps the data generation).
    public func setReadOnly(_ value: Bool) { readOnly = value }
    public var isReadOnly: Bool { readOnly }

    func requireWritable() throws {
        if readOnly { throw JournalStoreError.readOnly }
    }

    /// Monotonic count of successful saves since this store was created (snapshot-consistency check).
    public func generationCounter() -> UInt64 { writeCounter }

    // MARK: Reads

    public func dayContent(_ key: DateKey) throws -> DayContent {
        let entry = try fetchEntry(key)
        let s = key.string
        let attachments = try modelContext.fetchCount(
            FetchDescriptor<Attachment>(predicate: #Predicate { $0.entryDateKey == s }))
        let intentions = try modelContext.fetch(
            FetchDescriptor<WeeklyIntention>(predicate: #Predicate { $0.sourceSundayKey == s }))
        let hasIntention = intentions.contains {
            DayContent.isNonblank($0.text) || DayContent.isNonblank($0.category)
        }
        let followUps = try modelContext.fetch(
            FetchDescriptor<WeeklyIntention>(predicate: #Predicate { $0.followUpWrittenOnKey == s }))
        let hasFollowUp = followUps.contains { DayContent.isNonblank($0.followUpNote) }
        return DayContent(
            text: entry?.text ?? "", smileAnswer: entry?.smileAnswer, rotatingAnswer: entry?.rotatingAnswer,
            dayScore: entry?.dayScore, moodIDs: entry?.moodIDs ?? [], tagIDs: entry?.tagIDs ?? [],
            attachmentCount: attachments, hasIntention: hasIntention, hasFollowUpNote: hasFollowUp)
    }

    /// Exactly the model-input set for the review week containing `weekStart` (plan row 20).
    public func reflectionInput(weekStart: DateKey) throws -> ReflectionInput {
        let start = WeekCalendar.reviewWeekStart(containing: weekStart)
        let end = start.adding(days: 6)
        let lo = start.string
        let hi = end.string

        let tagNames = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Tag>()).map { ($0.id, $0.name) })
        let prompts = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(
                FetchDescriptor<PromptAssignment>(predicate: #Predicate { $0.dateKey >= lo && $0.dateKey <= hi })
            ).map { ($0.dateKey, $0.promptText) })

        var days: [ReflectionInput.Day] = []
        let entries = try modelContext.fetch(
            FetchDescriptor<DailyEntry>(predicate: #Predicate { $0.dateKey >= lo && $0.dateKey <= hi }))
        for e in entries {
            guard let key = DateKey(e.dateKey) else { continue }
            let names = e.tagIDs.compactMap { tagNames[$0] }
            let answered = DayContent.isNonblank(e.rotatingAnswer)
            let hasInput =
                DayContent.isNonblank(e.text) || DayContent.isNonblank(e.smileAnswer) || answered
                || e.dayScore != nil || !e.moodIDs.isEmpty || !names.isEmpty
            guard hasInput else { continue }
            days.append(
                ReflectionInput.Day(
                    dateKey: key, text: e.text, smileAnswer: e.smileAnswer,
                    rotatingPrompt: answered ? prompts[e.dateKey] : nil, rotatingAnswer: e.rotatingAnswer,
                    score: e.dayScore, moodIDs: e.moodIDs, tagNames: names))
        }

        // shortcut: loads every intention (one row per week), fine for decades of use
        let intentions = try modelContext.fetch(FetchDescriptor<WeeklyIntention>())
        var intention: ReflectionInput.Intention?
        if let row = intentions.first(where: { $0.sourceSundayKey == lo }),
            DayContent.isNonblank(row.text) || DayContent.isNonblank(row.category)
        {
            intention = ReflectionInput.Intention(text: row.text, category: row.category)
        }
        let followUps: [ReflectionInput.FollowUp] = intentions.compactMap { row in
            guard let note = row.followUpNote, DayContent.isNonblank(note),
                let wk = row.followUpWrittenOnKey, wk >= lo, wk <= hi, let key = DateKey(wk)
            else { return nil }
            return ReflectionInput.FollowUp(writtenOn: key, note: note)
        }

        let workouts = try modelContext.fetch(
            FetchDescriptor<WorkoutSnapshot>(predicate: #Predicate { $0.dateKey >= lo && $0.dateKey <= hi })
        ).compactMap { w -> ReflectionInput.Workout? in
            guard let key = DateKey(w.dateKey) else { return nil }
            return ReflectionInput.Workout(
                dateKey: key, activity: w.activityType, durationSeconds: w.durationSeconds,
                distanceMeters: w.distanceMeters)
        }
        return ReflectionInput(
            weekStart: start, days: days, intention: intention, followUps: followUps, workouts: workouts)
    }

    // MARK: Entries

    public func updateEntry(_ key: DateKey, _ change: EntryChange) throws -> StoreEffect {
        try requireWritable()
        let before = try contentFlags([key])
        let existing = try fetchEntry(key)
        let now = clock()
        // A new entry stays transient until the change proves it is not a no-op.
        let entry =
            existing
            ?? DailyEntry(dateKey: key.string, originalTimeZoneID: timeZone.identifier, createdAt: now, updatedAt: now)
        guard try apply(change, to: entry) else { return StoreEffect() }
        entry.updatedAt = now
        if existing == nil { modelContext.insert(entry) }
        return try commit(candidateDays: [key], before: before, bumpDays: [key])
    }

    private func apply(_ change: EntryChange, to entry: DailyEntry) throws -> Bool {
        switch change {
        case .text(let s):
            guard entry.text != s else { return false }
            entry.text = s
        case .smileAnswer(let s):
            let v = s?.isEmpty == true ? nil : s
            guard entry.smileAnswer != v else { return false }
            entry.smileAnswer = v
        case .rotatingAnswer(let s):
            let v = s?.isEmpty == true ? nil : s
            guard entry.rotatingAnswer != v else { return false }
            entry.rotatingAnswer = v
        case .score(let s):
            guard entry.dayScore != s?.rawValue else { return false }
            entry.dayScore = s?.rawValue
        case .moods(let ids):
            let v = MoodCatalog.normalize(ids)
            guard entry.moodIDs != v else { return false }
            entry.moodIDs = v
        case .tags(let ids):
            let known = Set(try modelContext.fetch(FetchDescriptor<Tag>()).map(\.id))
            var seen = Set<UUID>()
            let v = ids.filter { known.contains($0) && seen.insert($0).inserted }
            guard entry.tagIDs != v else { return false }
            entry.tagIDs = v
        }
        return true
    }

    // MARK: Prompts

    /// Persists the selector's choice when the day has no assignment; otherwise returns the stored one.
    public func assignPromptIfNeeded(
        _ key: DateKey, selector: PromptSelection
    ) throws -> (choice: PromptChoice, effect: StoreEffect) {
        try requireWritable()
        if let existing = try fetchAssignment(key) {
            return (PromptChoice(id: existing.promptID, text: existing.promptText), StoreEffect())
        }
        let choice = selector(key, try promptHistory())
        modelContext.insert(
            PromptAssignment(dateKey: key.string, promptID: choice.id, promptText: choice.text, assignedAt: clock()))
        return (choice, try commit(candidateDays: [], before: [:], bumpDays: []))
    }

    /// Every persisted assignment (imported and rerolled ones included), as the selector's history.
    private func promptHistory() throws -> [PromptHistoryItem] {
        try modelContext.fetch(FetchDescriptor<PromptAssignment>()).compactMap { a in
            DateKey(a.dateKey).map { PromptHistoryItem(dateKey: $0, promptID: a.promptID) }
        }
    }

    /// "Another prompt", choosing inside the store so the history read and the overwrite are one step.
    /// Refused while the rotating answer is nonblank.
    public func rerollPrompt(
        _ key: DateKey, selector: PromptReroll
    ) throws -> (choice: PromptChoice, effect: StoreEffect) {
        try requireWritable()
        if DayContent.isNonblank(try fetchEntry(key)?.rotatingAnswer) { throw JournalStoreError.promptAnswered }
        let choice = selector(key, try fetchAssignment(key)?.promptID, try promptHistory())
        return (choice, try rerollPrompt(key, candidate: choice))
    }

    /// "Another prompt": only while the rotating answer is blank. Never touches the answer.
    public func rerollPrompt(_ key: DateKey, candidate: PromptChoice) throws -> StoreEffect {
        try requireWritable()
        if DayContent.isNonblank(try fetchEntry(key)?.rotatingAnswer) { throw JournalStoreError.promptAnswered }
        if let a = try fetchAssignment(key) {
            guard a.promptID != candidate.id || a.promptText != candidate.text else { return StoreEffect() }
            a.promptID = candidate.id
            a.promptText = candidate.text
            a.assignedAt = clock()
        } else {
            modelContext.insert(
                PromptAssignment(
                    dateKey: key.string, promptID: candidate.id, promptText: candidate.text, assignedAt: clock()))
        }
        return try commit(candidateDays: [], before: [:], bumpDays: [])
    }

    // MARK: Tags

    /// Trimmed, case-insensitive unique: returns the existing tag's ID when a match exists.
    public func createTag(name: String) throws -> (id: UUID, effect: StoreEffect) {
        try requireWritable()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JournalStoreError.invalidTagName }
        if let match = try tag(named: trimmed) { return (match.id, StoreEffect()) }
        let tag = Tag(name: trimmed, createdAt: clock())
        modelContext.insert(tag)
        return (tag.id, try commit(candidateDays: [], before: [:], bumpDays: []))
    }

    public func renameTag(id: UUID, to name: String) throws -> StoreEffect {
        try requireWritable()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JournalStoreError.invalidTagName }
        guard let tag = try fetchTag(id) else { return StoreEffect() }
        if let clash = try self.tag(named: trimmed), clash.id != id { throw JournalStoreError.tagNameTaken }
        guard tag.name != trimmed else { return StoreEffect() }
        tag.name = trimmed
        let days = try entryDays(usingTag: id)
        return try commit(candidateDays: [], before: [:], bumpDays: days)
    }

    /// Removes the tag and its ID from every entry; reports every day whose content flipped and every week bumped.
    public func deleteTag(id: UUID) throws -> StoreEffect {
        try requireWritable()
        guard let tag = try fetchTag(id) else { return StoreEffect() }
        // shortcut: scans all entries, fine for a personal journal
        let affected = try modelContext.fetch(FetchDescriptor<DailyEntry>()).filter { $0.tagIDs.contains(id) }
        let days = Set(affected.compactMap { DateKey($0.dateKey) })
        let before = try contentFlags(days)
        let now = clock()
        for e in affected {
            e.tagIDs.removeAll { $0 == id }
            e.updatedAt = now
        }
        modelContext.delete(tag)
        return try commit(candidateDays: days, before: before, bumpDays: days)
    }

    // MARK: Intentions

    /// Every stored plan (a handful per year), as values the app can query with `IntentionQueries`.
    public func intentionPlans() throws -> [IntentionPlan] {
        try modelContext.fetch(FetchDescriptor<WeeklyIntention>()).compactMap { row in
            guard let sunday = DateKey(row.sourceSundayKey), let start = DateKey(row.targetStartKey),
                let end = DateKey(row.targetEndKey)
            else { return nil }
            return IntentionPlan(
                sourceSunday: sunday, targetStart: start, targetEnd: end, text: row.text, category: row.category,
                followUpNote: row.followUpNote, followUpWrittenOn: row.followUpWrittenOnKey.flatMap(DateKey.init),
                followUpSkipped: row.followUpSkipped)
        }
    }

    /// Blank text and no category removes the intention (kept as an empty row if it carries a follow-up).
    public func saveIntention(sunday: DateKey, text: String, category: String?) throws -> StoreEffect {
        try requireWritable()
        guard let target = WeekCalendar.intentionTarget(forSunday: sunday) else {
            throw JournalStoreError.notASunday
        }
        let cat = DayContent.isNonblank(category) ? category : nil
        let blank = !DayContent.isNonblank(text) && cat == nil
        let before = try contentFlags([sunday])
        let row = try fetchIntention(sunday)
        if let row {
            guard row.text != text || row.category != cat else { return StoreEffect() }
            if blank && row.followUpNote == nil && !row.followUpSkipped {
                modelContext.delete(row)
            } else {
                row.text = text
                row.category = cat
                row.targetStartKey = target.start.string
                row.targetEndKey = target.end.string
            }
        } else {
            guard !blank else { return StoreEffect() }
            modelContext.insert(
                WeeklyIntention(
                    sourceSundayKey: sunday.string, targetStartKey: target.start.string,
                    targetEndKey: target.end.string, text: text, category: cat))
        }
        return try commit(candidateDays: [sunday], before: before, bumpDays: [sunday])
    }

    /// Records the follow-up on the intention sourced `sourceSunday`. A nonblank note wins over `skipped`.
    public func saveFollowUp(sourceSunday: DateKey, writtenOn: DateKey, note: String?, skipped: Bool) throws
        -> StoreEffect
    {
        try requireWritable()
        guard let row = try fetchIntention(sourceSunday) else { throw JournalStoreError.intentionNotFound }
        let newNote = DayContent.isNonblank(note) ? note : nil
        let newSkipped = newNote == nil && skipped
        let newWrittenOn: String? = (newNote != nil || newSkipped) ? writtenOn.string : nil
        guard
            row.followUpNote != newNote || row.followUpSkipped != newSkipped || row.followUpWrittenOnKey != newWrittenOn
        else { return StoreEffect() }

        let oldWrittenOn = row.followUpWrittenOnKey.flatMap(DateKey.init)
        let newKey = newWrittenOn.flatMap(DateKey.init)
        let days = Set([oldWrittenOn, newKey].compactMap { $0 })
        let before = try contentFlags(days)
        let oldInput =
            DayContent.isNonblank(row.followUpNote) ? [row.followUpNote ?? "", row.followUpWrittenOnKey ?? ""] : []
        let newInput = newNote != nil ? [newNote ?? "", newWrittenOn ?? ""] : []
        row.followUpNote = newNote
        row.followUpSkipped = newSkipped
        row.followUpWrittenOnKey = newWrittenOn
        return try commit(
            candidateDays: days, before: before, bumpDays: oldInput == newInput ? [] : days)
    }

    // MARK: Attachment records (file I/O stays in the app)

    /// Attachments are not sent to the model, so this never bumps a review; it can flip day content.
    public func addAttachmentRecord(
        id: UUID, dateKey: DateKey, relativePath: String, uti: String, sha256: String, pixelSize: PixelSize? = nil
    ) throws -> StoreEffect {
        try requireWritable()
        let existing = try modelContext.fetchCount(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id }))
        guard existing == 0 else { return StoreEffect() }
        let before = try contentFlags([dateKey])
        modelContext.insert(
            Attachment(
                id: id, entryDateKey: dateKey.string, relativePath: relativePath, uti: uti, sha256: sha256,
                pixelSize: pixelSize, createdAt: clock()))
        return try commit(candidateDays: [dateKey], before: before, bumpDays: [])
    }

    /// Every attachment's id and file path, oldest first. Used to find a photo's file and to sweep orphans.
    public func attachmentRefs() throws -> [AttachmentRef] {
        try modelContext.fetch(
            FetchDescriptor<Attachment>(sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.relativePath)])
        )
        .map { AttachmentRef(id: $0.id, relativePath: $0.relativePath) }
    }

    public func deleteAttachmentRecord(id: UUID) throws -> StoreEffect {
        try requireWritable()
        var d = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let record = try modelContext.fetch(d).first else { return StoreEffect() }
        let days = Set([DateKey(record.entryDateKey)].compactMap { $0 })
        let before = try contentFlags(days)
        modelContext.delete(record)
        return try commit(candidateDays: days, before: before, bumpDays: [])
    }

    // MARK: Workouts

    /// Identical data is a no-op. Only changes to what the model reads (day, activity, duration, distance) bump.
    public func upsertWorkouts(_ inputs: [WorkoutInput]) throws -> StoreEffect {
        try requireWritable()
        var latest: [UUID: WorkoutInput] = [:]
        for i in inputs { latest[i.healthKitUUID] = i }
        var changed = false
        var bumpDays = Set<DateKey>()
        for i in latest.values {
            let id = i.healthKitUUID
            var d = FetchDescriptor<WorkoutSnapshot>(predicate: #Predicate { $0.healthKitUUID == id })
            d.fetchLimit = 1
            if let w = try modelContext.fetch(d).first {
                let modelInputChanged =
                    w.dateKey != i.dateKey.string || w.activityType != i.activityType
                    || w.durationSeconds != i.durationSeconds || w.distanceMeters != i.distanceMeters
                let otherChanged =
                    w.sourceName != i.sourceName || w.start != i.start || w.end != i.end
                    || w.timeZoneID != i.timeZoneID || w.energyKcal != i.energyKcal
                guard modelInputChanged || otherChanged else { continue }
                changed = true
                if modelInputChanged {
                    if let old = DateKey(w.dateKey) { bumpDays.insert(old) }
                    bumpDays.insert(i.dateKey)
                }
                w.sourceName = i.sourceName
                w.activityType = i.activityType
                w.start = i.start
                w.end = i.end
                w.dateKey = i.dateKey.string
                w.timeZoneID = i.timeZoneID
                w.durationSeconds = i.durationSeconds
                w.distanceMeters = i.distanceMeters
                w.energyKcal = i.energyKcal
            } else {
                changed = true
                bumpDays.insert(i.dateKey)
                modelContext.insert(
                    WorkoutSnapshot(
                        healthKitUUID: id, sourceName: i.sourceName, activityType: i.activityType, start: i.start,
                        end: i.end, dateKey: i.dateKey.string, timeZoneID: i.timeZoneID,
                        durationSeconds: i.durationSeconds, distanceMeters: i.distanceMeters, energyKcal: i.energyKcal))
            }
        }
        guard changed else { return StoreEffect() }
        return try commit(candidateDays: [], before: [:], bumpDays: bumpDays)
    }

    public func deleteWorkouts(uuids: [UUID]) throws -> StoreEffect {
        try requireWritable()
        var bumpDays = Set<DateKey>()
        var changed = false
        for id in Set(uuids) {
            var d = FetchDescriptor<WorkoutSnapshot>(predicate: #Predicate { $0.healthKitUUID == id })
            d.fetchLimit = 1
            guard let w = try modelContext.fetch(d).first else { continue }
            if let key = DateKey(w.dateKey) { bumpDays.insert(key) }
            modelContext.delete(w)
            changed = true
        }
        guard changed else { return StoreEffect() }
        return try commit(candidateDays: [], before: [:], bumpDays: bumpDays)
    }

    /// Deletes every workout whose UUID is not in `keeping`. After a restore, a full Health sync names what still
    /// exists; the rest were deleted in Health since the backup was made.
    public func pruneWorkouts(keeping: Set<UUID>) throws -> StoreEffect {
        try requireWritable()
        var bumpDays = Set<DateKey>()
        var changed = false
        for w in try modelContext.fetch(FetchDescriptor<WorkoutSnapshot>()) where !keeping.contains(w.healthKitUUID) {
            if let key = DateKey(w.dateKey) { bumpDays.insert(key) }
            modelContext.delete(w)
            changed = true
        }
        guard changed else { return StoreEffect() }
        return try commit(candidateDays: [], before: [:], bumpDays: bumpDays)
    }

    // MARK: Reviews

    /// Increments `sourceRevision` on the week's existing review row and purges its narrative, keeping the
    /// "more of this" fields. Returns false when the week has no review row. Does not save.
    @discardableResult
    func bumpWeekRevision(for dayKey: DateKey) throws -> Bool {
        let week = WeekCalendar.reviewWeekStart(containing: dayKey)
        guard let review = try fetchReview(week) else { return false }
        review.sourceRevision += 1
        purge(review, reason: "source changed")
        return true
    }

    /// True when the week has a narrative whose fingerprint matches the current model input. A mismatch purges
    /// it. In read-only mode a mismatch returns false without writing.
    public func validateNarrative(weekStart: DateKey) throws -> Bool {
        let week = WeekCalendar.reviewWeekStart(containing: weekStart)
        guard let review = try fetchReview(week), review.narrativeJSON != nil else { return false }
        let current = try ReviewFingerprint.compute(try reflectionInput(weekStart: week))
        if review.inputFingerprint == current { return true }
        guard !readOnly else { return false }
        purge(review, reason: "input changed")
        try modelContext.save()
        writeCounter &+= 1
        return false
    }

    /// Read-only check that `stored` is the fingerprint of the current model input for the week. Never purges.
    func fingerprintMatches(weekStart: DateKey, stored: String?) throws -> Bool {
        guard let stored else { return false }
        return stored == (try ReviewFingerprint.compute(try reflectionInput(weekStart: weekStart)))
    }

    private func purge(_ review: WeeklyReview, reason: String) {
        guard review.narrativeJSON != nil || review.inputFingerprint != nil else { return }
        review.narrativeJSON = nil
        review.inputFingerprint = nil
        review.generatedAt = nil
        review.purgeReason = reason
    }

    // MARK: Helpers

    /// Bumps each distinct week once, saves, then reports which candidate days flipped. Rolls back on failure.
    func commit(candidateDays: Set<DateKey>, before: [DateKey: Bool], bumpDays: Set<DateKey>) throws
        -> StoreEffect
    {
        do {
            var effect = StoreEffect(dirty: true)
            for week in Set(bumpDays.map { WeekCalendar.reviewWeekStart(containing: $0) }) {
                if try bumpWeekRevision(for: week) { effect.revisionBumpedWeeks.insert(week) }
            }
            try modelContext.save()
            writeCounter &+= 1
            let after = try contentFlags(candidateDays)
            effect.contentChangedDays = Set(candidateDays.filter { before[$0] != after[$0] })
            return effect
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func contentFlags(_ days: Set<DateKey>) throws -> [DateKey: Bool] {
        var flags: [DateKey: Bool] = [:]
        for d in days { flags[d] = try dayContent(d).hasUserContent }
        return flags
    }

    private func entryDays(usingTag id: UUID) throws -> Set<DateKey> {
        // shortcut: scans all entries, fine for a personal journal
        Set(
            try modelContext.fetch(FetchDescriptor<DailyEntry>()).filter { $0.tagIDs.contains(id) }
                .compactMap { DateKey($0.dateKey) })
    }

    private func fetchEntry(_ key: DateKey) throws -> DailyEntry? {
        let s = key.string
        var d = FetchDescriptor<DailyEntry>(predicate: #Predicate { $0.dateKey == s })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func fetchAssignment(_ key: DateKey) throws -> PromptAssignment? {
        let s = key.string
        var d = FetchDescriptor<PromptAssignment>(predicate: #Predicate { $0.dateKey == s })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func fetchIntention(_ sunday: DateKey) throws -> WeeklyIntention? {
        let s = sunday.string
        var d = FetchDescriptor<WeeklyIntention>(predicate: #Predicate { $0.sourceSundayKey == s })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func fetchReview(_ week: DateKey) throws -> WeeklyReview? {
        let s = week.string
        var d = FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func fetchTag(_ id: UUID) throws -> Tag? {
        var d = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func tag(named name: String) throws -> Tag? {
        let folded = name.lowercased()
        return try modelContext.fetch(FetchDescriptor<Tag>()).first { $0.name.lowercased() == folded }
    }
}
