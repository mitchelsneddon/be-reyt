import Foundation
import SwiftData

/// The two reminder settings, read and written through the store (A2).
public struct ReminderSettings: Sendable, Equatable {
    public var enabled: Bool
    public var hour: Int
    public init(enabled: Bool, hour: Int) {
        self.enabled = enabled
        self.hour = hour
    }
}

extension JournalStore {
    /// The stored reminder settings, or the model's defaults when no settings row exists yet.
    public func reminderSettings() throws -> ReminderSettings {
        let row = try modelContext.fetch(FetchDescriptor<AppSettings>()).first ?? AppSettings()
        return ReminderSettings(enabled: row.reminderEnabled, hour: row.reminderHour)
    }

    /// Writes the reminder settings (creating the single settings row on first write). Hour is clamped to 0...23.
    public func updateReminderSettings(enabled: Bool, hour: Int) throws -> StoreEffect {
        try requireWritable()
        let hour = min(23, max(0, hour))
        let existing = try modelContext.fetch(FetchDescriptor<AppSettings>()).first
        if let existing {
            guard existing.reminderEnabled != enabled || existing.reminderHour != hour else { return StoreEffect() }
            existing.reminderEnabled = enabled
            existing.reminderHour = hour
        } else {
            modelContext.insert(AppSettings(reminderEnabled: enabled, reminderHour: hour))
        }
        return try commit(candidateDays: [], before: [:], bumpDays: [])
    }

    /// The days from `start` through `end` inclusive that have user content (`DayContent.hasUserContent`).
    public func contentDays(from start: DateKey, through end: DateKey) throws -> Set<DateKey> {
        var result: Set<DateKey> = []
        var key = start
        while key <= end {
            if try dayContent(key).hasUserContent { result.insert(key) }
            key = key.adding(days: 1)
        }
        return result
    }
}
