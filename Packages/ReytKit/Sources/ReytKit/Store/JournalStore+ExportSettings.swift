import Foundation
import SwiftData

extension JournalStore {
    /// Whether readable exports include the workouts copied from Apple Health (off when no settings row exists).
    public func includeWorkoutsInExports() throws -> Bool {
        try modelContext.fetch(FetchDescriptor<AppSettings>()).first?.includeWorkoutsInExports ?? false
    }

    /// Writes the include-workouts choice (creating the single settings row on first write).
    public func updateIncludeWorkoutsInExports(_ include: Bool) throws -> StoreEffect {
        try requireWritable()
        if let existing = try modelContext.fetch(FetchDescriptor<AppSettings>()).first {
            guard existing.includeWorkoutsInExports != include else { return StoreEffect() }
            existing.includeWorkoutsInExports = include
        } else {
            modelContext.insert(AppSettings(includeWorkoutsInExports: include))
        }
        return try commit(candidateDays: [], before: [:], bumpDays: [])
    }
}
