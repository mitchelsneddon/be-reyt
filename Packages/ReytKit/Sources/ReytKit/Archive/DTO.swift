import Foundation
import SwiftData

// Archive boundary types (A6): plain `Codable` values, separate from the `@Model` classes. Every persisted
// property of every SchemaV1 record has a DTO field of the same name; the `CodingKeys` enums are `CaseIterable`
// so a test can compare them with the schema's own property list.

// MARK: Coding

enum ArchiveCoding {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(fractional.format(date))
        }
        return e
    }

    /// Unknown fields are ignored (default `Decodable` behaviour). Dates accept fractional seconds or whole.
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = try? fractional.parse(raw) { return date }
            if let date = try? whole.parse(raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "not an ISO8601 date"))
        }
        return d
    }
}

// MARK: Records

public struct DailyEntryDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var dateKey: String
    public var originalTimeZoneID: String
    public var text: String
    public var smileAnswer: String?
    public var rotatingAnswer: String?
    public var dayScore: Int?
    public var moodIDs: [String]
    public var tagIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, dateKey, originalTimeZoneID, text, smileAnswer, rotatingAnswer, dayScore, moodIDs, tagIDs
        case createdAt, updatedAt
    }
}

extension DailyEntryDTO {
    init(_ m: DailyEntry) {
        self.init(
            id: m.id, dateKey: m.dateKey, originalTimeZoneID: m.originalTimeZoneID, text: m.text,
            smileAnswer: m.smileAnswer, rotatingAnswer: m.rotatingAnswer, dayScore: m.dayScore, moodIDs: m.moodIDs,
            tagIDs: m.tagIDs, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    func makeModel() -> DailyEntry {
        DailyEntry(
            id: id, dateKey: dateKey, originalTimeZoneID: originalTimeZoneID, text: text, smileAnswer: smileAnswer,
            rotatingAnswer: rotatingAnswer, dayScore: dayScore, moodIDs: moodIDs, tagIDs: tagIDs,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

public struct AppSettingsDTO: Codable, Equatable, Sendable {
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var includeWorkoutsInExports: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case reminderEnabled, reminderHour, includeWorkoutsInExports
    }
}

extension AppSettingsDTO {
    init(_ m: AppSettings) {
        self.init(
            reminderEnabled: m.reminderEnabled, reminderHour: m.reminderHour,
            includeWorkoutsInExports: m.includeWorkoutsInExports)
    }

    /// The model's own defaults, for a journal with no settings row yet.
    static var defaults: AppSettingsDTO { AppSettingsDTO(AppSettings()) }

    func makeModel() -> AppSettings {
        AppSettings(
            reminderEnabled: reminderEnabled, reminderHour: reminderHour,
            includeWorkoutsInExports: includeWorkoutsInExports)
    }
}

public struct PromptAssignmentDTO: Codable, Equatable, Sendable {
    public var dateKey: String
    public var promptID: String
    public var promptText: String
    public var assignedAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable { case dateKey, promptID, promptText, assignedAt }
}

extension PromptAssignmentDTO {
    init(_ m: PromptAssignment) {
        self.init(dateKey: m.dateKey, promptID: m.promptID, promptText: m.promptText, assignedAt: m.assignedAt)
    }

    func makeModel() -> PromptAssignment {
        PromptAssignment(dateKey: dateKey, promptID: promptID, promptText: promptText, assignedAt: assignedAt)
    }
}

public struct TagDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable { case id, name, createdAt }
}

extension TagDTO {
    init(_ m: Tag) { self.init(id: m.id, name: m.name, createdAt: m.createdAt) }
    func makeModel() -> Tag { Tag(id: id, name: name, createdAt: createdAt) }
}

public struct AttachmentDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var entryDateKey: String
    public var relativePath: String
    public var uti: String
    public var sha256: String
    public var pixelSize: PixelSize?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, entryDateKey, relativePath, uti, sha256, pixelSize, createdAt
    }
}

extension AttachmentDTO {
    init(_ m: Attachment) {
        self.init(
            id: m.id, entryDateKey: m.entryDateKey, relativePath: m.relativePath, uti: m.uti, sha256: m.sha256,
            pixelSize: m.pixelSize, createdAt: m.createdAt)
    }

    func makeModel() -> Attachment {
        Attachment(
            id: id, entryDateKey: entryDateKey, relativePath: relativePath, uti: uti, sha256: sha256,
            pixelSize: pixelSize, createdAt: createdAt)
    }
}

public struct WorkoutSnapshotDTO: Codable, Equatable, Sendable {
    public var healthKitUUID: UUID
    public var sourceName: String
    public var activityType: String
    public var start: Date
    public var end: Date
    public var dateKey: String
    public var timeZoneID: String?
    public var durationSeconds: Double
    public var distanceMeters: Double?
    public var energyKcal: Double?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case healthKitUUID, sourceName, activityType, start, end, dateKey, timeZoneID, durationSeconds
        case distanceMeters, energyKcal
    }
}

extension WorkoutSnapshotDTO {
    init(_ m: WorkoutSnapshot) {
        self.init(
            healthKitUUID: m.healthKitUUID, sourceName: m.sourceName, activityType: m.activityType, start: m.start,
            end: m.end, dateKey: m.dateKey, timeZoneID: m.timeZoneID, durationSeconds: m.durationSeconds,
            distanceMeters: m.distanceMeters, energyKcal: m.energyKcal)
    }

    func makeModel() -> WorkoutSnapshot {
        WorkoutSnapshot(
            healthKitUUID: healthKitUUID, sourceName: sourceName, activityType: activityType, start: start,
            end: end, dateKey: dateKey, timeZoneID: timeZoneID, durationSeconds: durationSeconds,
            distanceMeters: distanceMeters, energyKcal: energyKcal)
    }
}

public struct WeeklyReviewDTO: Codable, Equatable, Sendable {
    public var weekStartKey: String
    public var weekEndKey: String
    public var timeZoneID: String
    public var unlockedAt: Date
    public var sourceRevision: Int
    public var narrativeJSON: String?
    public var inputFingerprint: String?
    public var generatedAt: Date?
    public var promptVersion: Int?
    public var osBuild: String?
    public var purgeReason: String?
    public var moreOfThisText: String?
    public var moreOfThisTargetStartKey: String?
    public var moreOfThisTargetEndKey: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case weekStartKey, weekEndKey, timeZoneID, unlockedAt, sourceRevision, narrativeJSON, inputFingerprint
        case generatedAt, promptVersion, osBuild, purgeReason, moreOfThisText, moreOfThisTargetStartKey
        case moreOfThisTargetEndKey
    }
}

extension WeeklyReviewDTO {
    init(_ m: WeeklyReview) {
        self.init(
            weekStartKey: m.weekStartKey, weekEndKey: m.weekEndKey, timeZoneID: m.timeZoneID,
            unlockedAt: m.unlockedAt, sourceRevision: m.sourceRevision, narrativeJSON: m.narrativeJSON,
            inputFingerprint: m.inputFingerprint, generatedAt: m.generatedAt, promptVersion: m.promptVersion,
            osBuild: m.osBuild, purgeReason: m.purgeReason, moreOfThisText: m.moreOfThisText,
            moreOfThisTargetStartKey: m.moreOfThisTargetStartKey, moreOfThisTargetEndKey: m.moreOfThisTargetEndKey)
    }

    func makeModel() -> WeeklyReview {
        WeeklyReview(
            weekStartKey: weekStartKey, weekEndKey: weekEndKey, timeZoneID: timeZoneID, unlockedAt: unlockedAt,
            sourceRevision: sourceRevision, narrativeJSON: narrativeJSON, inputFingerprint: inputFingerprint,
            generatedAt: generatedAt, promptVersion: promptVersion, osBuild: osBuild, purgeReason: purgeReason,
            moreOfThisText: moreOfThisText, moreOfThisTargetStartKey: moreOfThisTargetStartKey,
            moreOfThisTargetEndKey: moreOfThisTargetEndKey)
    }

    /// The same review without its narrative, mirroring `JournalStore`'s purge (other fields kept).
    func omittingNarrative() -> WeeklyReviewDTO {
        var copy = self
        copy.narrativeJSON = nil
        copy.inputFingerprint = nil
        copy.generatedAt = nil
        copy.purgeReason = "input changed"
        return copy
    }
}

public struct WeeklyIntentionDTO: Codable, Equatable, Sendable {
    public var sourceSundayKey: String
    public var targetStartKey: String
    public var targetEndKey: String
    public var text: String
    public var category: String?
    public var followUpNote: String?
    public var followUpWrittenOnKey: String?
    public var followUpSkipped: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceSundayKey, targetStartKey, targetEndKey, text, category, followUpNote, followUpWrittenOnKey
        case followUpSkipped
    }
}

extension WeeklyIntentionDTO {
    init(_ m: WeeklyIntention) {
        self.init(
            sourceSundayKey: m.sourceSundayKey, targetStartKey: m.targetStartKey, targetEndKey: m.targetEndKey,
            text: m.text, category: m.category, followUpNote: m.followUpNote,
            followUpWrittenOnKey: m.followUpWrittenOnKey, followUpSkipped: m.followUpSkipped)
    }

    func makeModel() -> WeeklyIntention {
        WeeklyIntention(
            sourceSundayKey: sourceSundayKey, targetStartKey: targetStartKey, targetEndKey: targetEndKey,
            text: text, category: category, followUpNote: followUpNote, followUpWrittenOnKey: followUpWrittenOnKey,
            followUpSkipped: followUpSkipped)
    }
}

public struct ImportRecordDTO: Codable, Equatable, Sendable {
    public var sourceIdentityHash: String
    public var importedAt: Date
    public var sourceArchiveHash: String
    public var targetDateKey: String
    public var sourceTitle: String?
    public var sourceTimestamp: Date?
    public var sectionIndex: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceIdentityHash, importedAt, sourceArchiveHash, targetDateKey, sourceTitle, sourceTimestamp
        case sectionIndex
    }
}

extension ImportRecordDTO {
    init(_ m: ImportRecord) {
        self.init(
            sourceIdentityHash: m.sourceIdentityHash, importedAt: m.importedAt,
            sourceArchiveHash: m.sourceArchiveHash, targetDateKey: m.targetDateKey, sourceTitle: m.sourceTitle,
            sourceTimestamp: m.sourceTimestamp, sectionIndex: m.sectionIndex)
    }

    func makeModel() -> ImportRecord {
        ImportRecord(
            sourceIdentityHash: sourceIdentityHash, importedAt: importedAt, sourceArchiveHash: sourceArchiveHash,
            targetDateKey: targetDateKey, sourceTitle: sourceTitle, sourceTimestamp: sourceTimestamp,
            sectionIndex: sectionIndex)
    }
}

// MARK: data.json

public struct ArchiveData: Codable, Equatable, Sendable {
    public var entries: [DailyEntryDTO]
    public var tags: [TagDTO]
    public var attachments: [AttachmentDTO]
    public var promptAssignments: [PromptAssignmentDTO]
    public var intentions: [WeeklyIntentionDTO]
    public var reviews: [WeeklyReviewDTO]
    public var workouts: [WorkoutSnapshotDTO]
    public var importRecords: [ImportRecordDTO]
    public var settings: AppSettingsDTO

    enum CodingKeys: String, CodingKey, CaseIterable {
        case entries, tags, attachments, promptAssignments, intentions, reviews, workouts, importRecords, settings
    }

    /// First and last day among entries and attachments (days that can hold content), nil when there are none.
    public var dateRange: ArchiveManifest.DateRange? {
        let keys = entries.map(\.dateKey) + attachments.map(\.entryDateKey)
        guard let first = keys.min(), let last = keys.max() else { return nil }
        return ArchiveManifest.DateRange(first: first, last: last)
    }

    /// Every record in the context, in a stable order so two fetches of equal data compare equal.
    static func fetch(from context: ModelContext) throws -> ArchiveData {
        ArchiveData(
            entries: try context.fetch(FetchDescriptor<DailyEntry>()).map(DailyEntryDTO.init)
                .sorted { $0.dateKey < $1.dateKey },
            tags: try context.fetch(FetchDescriptor<Tag>()).map(TagDTO.init).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            attachments: try context.fetch(FetchDescriptor<Attachment>()).map(AttachmentDTO.init)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            promptAssignments: try context.fetch(FetchDescriptor<PromptAssignment>()).map(PromptAssignmentDTO.init)
                .sorted { $0.dateKey < $1.dateKey },
            intentions: try context.fetch(FetchDescriptor<WeeklyIntention>()).map(WeeklyIntentionDTO.init)
                .sorted { $0.sourceSundayKey < $1.sourceSundayKey },
            reviews: try context.fetch(FetchDescriptor<WeeklyReview>()).map(WeeklyReviewDTO.init)
                .sorted { $0.weekStartKey < $1.weekStartKey },
            workouts: try context.fetch(FetchDescriptor<WorkoutSnapshot>()).map(WorkoutSnapshotDTO.init)
                .sorted { $0.healthKitUUID.uuidString < $1.healthKitUUID.uuidString },
            importRecords: try context.fetch(FetchDescriptor<ImportRecord>()).map(ImportRecordDTO.init)
                .sorted { $0.sourceIdentityHash < $1.sourceIdentityHash },
            settings: try context.fetch(FetchDescriptor<AppSettings>()).first.map(AppSettingsDTO.init) ?? .defaults)
    }

    /// Inserts every record (plus exactly one settings row). The caller saves.
    func insert(into context: ModelContext) {
        for r in entries { context.insert(r.makeModel()) }
        for r in tags { context.insert(r.makeModel()) }
        for r in attachments { context.insert(r.makeModel()) }
        for r in promptAssignments { context.insert(r.makeModel()) }
        for r in intentions { context.insert(r.makeModel()) }
        for r in reviews { context.insert(r.makeModel()) }
        for r in workouts { context.insert(r.makeModel()) }
        for r in importRecords { context.insert(r.makeModel()) }
        context.insert(settings.makeModel())
    }
}

// MARK: manifest.json

public struct ArchiveManifest: Codable, Equatable, Sendable {
    public static let formatName = "be-reyt-archive"
    public static let supportedSchemaVersion = 1

    public enum Kind: String, Codable, Sendable { case portable, snapshot }

    public struct Counts: Codable, Equatable, Sendable {
        public var entries: Int
        public var attachments: Int
        public var intentions: Int
        public var reviews: Int
        public var tags: Int
        public var workouts: Int
        public var promptAssignments: Int
    }

    public struct DateRange: Codable, Equatable, Sendable {
        public var first: String
        public var last: String
    }

    public struct Attachment: Codable, Equatable, Sendable {
        public var id: UUID
        public var ext: String
        public var sha256: String
        public var bytes: Int
        /// Snapshot kind only: the name of the encrypted blob holding the file.
        public var blob: String?
    }

    public var format: String
    public var kind: Kind
    public var schemaVersion: Int
    public var appVersion: String
    public var createdAt: Date
    public var timeZone: String
    public var lineageID: UUID
    public var counts: Counts
    public var dateRange: DateRange?
    public var attachments: [Attachment]
    /// Things the export could not include (e.g. `missing-attachment`), one entry each. Absent in older archives.
    public var warnings: [String]?
}

extension ArchiveManifest.Counts {
    public init(_ data: ArchiveData) {
        self.init(
            entries: data.entries.count, attachments: data.attachments.count, intentions: data.intentions.count,
            reviews: data.reviews.count, tags: data.tags.count, workouts: data.workouts.count,
            promptAssignments: data.promptAssignments.count)
    }
}
