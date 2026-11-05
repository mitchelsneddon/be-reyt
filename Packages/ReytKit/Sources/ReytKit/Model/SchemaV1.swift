import Foundation
import SwiftData

/// Pixel dimensions of an attachment image.
public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Journal schema. Device-local records (`HealthAnchor`, `BackupState`) are NOT part of it.
/// Freezes at the first real-use install; later changes are `SchemaV2` plus a migration stage and test.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            DailyEntry.self, AppSettings.self, PromptAssignment.self, Tag.self, Attachment.self,
            WorkoutSnapshot.self, WeeklyReview.self, WeeklyIntention.self, ImportRecord.self,
        ]
    }

    @Model
    public final class DailyEntry {
        public var id: UUID
        @Attribute(.unique) public var dateKey: String
        public var originalTimeZoneID: String
        public var text: String
        public var smileAnswer: String?
        public var rotatingAnswer: String?
        public var dayScore: Int?
        public var moodIDs: [String]
        public var tagIDs: [UUID]
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), dateKey: String, originalTimeZoneID: String, text: String = "",
            smileAnswer: String? = nil, rotatingAnswer: String? = nil, dayScore: Int? = nil,
            moodIDs: [String] = [], tagIDs: [UUID] = [], createdAt: Date, updatedAt: Date
        ) {
            self.id = id
            self.dateKey = dateKey
            self.originalTimeZoneID = originalTimeZoneID
            self.text = text
            self.smileAnswer = smileAnswer
            self.rotatingAnswer = rotatingAnswer
            self.dayScore = dayScore
            self.moodIDs = moodIDs
            self.tagIDs = tagIDs
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    /// Single row.
    @Model
    public final class AppSettings {
        public var reminderEnabled: Bool
        public var reminderHour: Int
        public var includeWorkoutsInExports: Bool

        public init(reminderEnabled: Bool = true, reminderHour: Int = 21, includeWorkoutsInExports: Bool = false) {
            self.reminderEnabled = reminderEnabled
            self.reminderHour = reminderHour
            self.includeWorkoutsInExports = includeWorkoutsInExports
        }
    }

    @Model
    public final class PromptAssignment {
        @Attribute(.unique) public var dateKey: String
        public var promptID: String
        public var promptText: String
        public var assignedAt: Date

        public init(dateKey: String, promptID: String, promptText: String, assignedAt: Date) {
            self.dateKey = dateKey
            self.promptID = promptID
            self.promptText = promptText
            self.assignedAt = assignedAt
        }
    }

    /// Name uniqueness is case-insensitive, which SwiftData cannot express, so `JournalStore` enforces it.
    @Model
    public final class Tag {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var createdAt: Date

        public init(id: UUID = UUID(), name: String, createdAt: Date) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }
    }

    @Model
    public final class Attachment {
        @Attribute(.unique) public var id: UUID
        public var entryDateKey: String
        public var relativePath: String
        public var uti: String
        public var sha256: String
        public var pixelSize: PixelSize?
        public var createdAt: Date

        public init(
            id: UUID = UUID(), entryDateKey: String, relativePath: String, uti: String, sha256: String,
            pixelSize: PixelSize? = nil, createdAt: Date
        ) {
            self.id = id
            self.entryDateKey = entryDateKey
            self.relativePath = relativePath
            self.uti = uti
            self.sha256 = sha256
            self.pixelSize = pixelSize
            self.createdAt = createdAt
        }
    }

    @Model
    public final class WorkoutSnapshot {
        @Attribute(.unique) public var healthKitUUID: UUID
        public var sourceName: String
        /// Stable string identifier mapped from `HKWorkoutActivityType` at the HealthKit boundary (A6).
        public var activityType: String
        public var start: Date
        public var end: Date
        public var dateKey: String
        public var timeZoneID: String?
        public var durationSeconds: Double
        public var distanceMeters: Double?
        public var energyKcal: Double?

        public init(
            healthKitUUID: UUID, sourceName: String, activityType: String, start: Date, end: Date, dateKey: String,
            timeZoneID: String? = nil, durationSeconds: Double, distanceMeters: Double? = nil,
            energyKcal: Double? = nil
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

    @Model
    public final class WeeklyReview {
        @Attribute(.unique) public var weekStartKey: String
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

        public init(
            weekStartKey: String, weekEndKey: String, timeZoneID: String, unlockedAt: Date, sourceRevision: Int = 0,
            narrativeJSON: String? = nil, inputFingerprint: String? = nil, generatedAt: Date? = nil,
            promptVersion: Int? = nil, osBuild: String? = nil, purgeReason: String? = nil,
            moreOfThisText: String? = nil, moreOfThisTargetStartKey: String? = nil,
            moreOfThisTargetEndKey: String? = nil
        ) {
            self.weekStartKey = weekStartKey
            self.weekEndKey = weekEndKey
            self.timeZoneID = timeZoneID
            self.unlockedAt = unlockedAt
            self.sourceRevision = sourceRevision
            self.narrativeJSON = narrativeJSON
            self.inputFingerprint = inputFingerprint
            self.generatedAt = generatedAt
            self.promptVersion = promptVersion
            self.osBuild = osBuild
            self.purgeReason = purgeReason
            self.moreOfThisText = moreOfThisText
            self.moreOfThisTargetStartKey = moreOfThisTargetStartKey
            self.moreOfThisTargetEndKey = moreOfThisTargetEndKey
        }
    }

    @Model
    public final class WeeklyIntention {
        @Attribute(.unique) public var sourceSundayKey: String
        public var targetStartKey: String
        public var targetEndKey: String
        public var text: String
        public var category: String?
        public var followUpNote: String?
        public var followUpWrittenOnKey: String?
        public var followUpSkipped: Bool

        public init(
            sourceSundayKey: String, targetStartKey: String, targetEndKey: String, text: String,
            category: String? = nil, followUpNote: String? = nil, followUpWrittenOnKey: String? = nil,
            followUpSkipped: Bool = false
        ) {
            self.sourceSundayKey = sourceSundayKey
            self.targetStartKey = targetStartKey
            self.targetEndKey = targetEndKey
            self.text = text
            self.category = category
            self.followUpNote = followUpNote
            self.followUpWrittenOnKey = followUpWrittenOnKey
            self.followUpSkipped = followUpSkipped
        }
    }

    /// One per source entry in an Apple Journal import.
    @Model
    public final class ImportRecord {
        @Attribute(.unique) public var sourceIdentityHash: String
        public var importedAt: Date
        public var sourceArchiveHash: String
        public var targetDateKey: String
        public var sourceTitle: String?
        public var sourceTimestamp: Date?
        public var sectionIndex: Int

        public init(
            sourceIdentityHash: String, importedAt: Date, sourceArchiveHash: String, targetDateKey: String,
            sourceTitle: String? = nil, sourceTimestamp: Date? = nil, sectionIndex: Int
        ) {
            self.sourceIdentityHash = sourceIdentityHash
            self.importedAt = importedAt
            self.sourceArchiveHash = sourceArchiveHash
            self.targetDateKey = targetDateKey
            self.sourceTitle = sourceTitle
            self.sourceTimestamp = sourceTimestamp
            self.sectionIndex = sectionIndex
        }
    }
}

public typealias DailyEntry = SchemaV1.DailyEntry
public typealias AppSettings = SchemaV1.AppSettings
public typealias PromptAssignment = SchemaV1.PromptAssignment
public typealias Tag = SchemaV1.Tag
public typealias Attachment = SchemaV1.Attachment
public typealias WorkoutSnapshot = SchemaV1.WorkoutSnapshot
public typealias WeeklyReview = SchemaV1.WeeklyReview
public typealias WeeklyIntention = SchemaV1.WeeklyIntention
public typealias ImportRecord = SchemaV1.ImportRecord

public enum BeReytMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
