import Foundation
import SwiftData

/// Apple Journal import: one transaction for all text and source records.
extension JournalStore {
    /// Identity hashes of every source entry imported so far.
    public func importedSourceHashes() throws -> Set<String> {
        Set(try modelContext.fetch(FetchDescriptor<ImportRecord>()).map(\.sourceIdentityHash))
    }

    /// Days whose entry already holds written text.
    public func daysWithText() throws -> Set<DateKey> {
        // shortcut: scans every entry, fine for a personal journal
        Set(
            try modelContext.fetch(FetchDescriptor<DailyEntry>())
                .filter { DayContent.isNonblank($0.text) }.compactMap { DateKey($0.dateKey) })
    }

    /// Writes the plan's text and one `ImportRecord` per source entry, all or nothing.
    ///
    /// - A day with no text gets a new entry (zone = this store's current zone).
    /// - A day that already has text follows `resolutions` (default `.append`); `.skip` writes nothing for it,
    ///   not even records, so a later import can still bring it in.
    /// - Entries whose hash already has a record are skipped, so importing the same export twice adds nothing.
    /// - Existing entries keep their prompts, score, moods and tags: only `text` changes.
    /// - Weeks containing a changed day lose their generated narrative through the usual `commit` bump.
    ///
    /// Photos are not part of this transaction: the app copies files into place afterwards, one at a time, and a
    /// photo that fails is reported without undoing the text. That avoids records that point at missing files.
    public func commitAppleJournalImport(
        plan: AppleJournalImportPlan, resolutions: [DateKey: AppleJournalConflictResolution], importedAt: Date
    ) throws -> StoreEffect {
        try requireWritable()
        let known = try importedSourceHashes()
        var changedDays = Set<DateKey>()
        var before: [DateKey: Bool] = [:]
        do {
            for day in plan.days {
                let fresh = day.entries.filter { !known.contains($0.identityHash) }
                guard !fresh.isEmpty else { continue }
                let existing = try fetchEntry(day.dateKey)
                let hasText = DayContent.isNonblank(existing?.text)
                if hasText, (resolutions[day.dateKey] ?? .append) == .skip { continue }

                before[day.dateKey] = try contentFlags([day.dateKey])[day.dateKey]
                changedDays.insert(day.dateKey)
                let composed = AppleJournalDay(dateKey: day.dateKey, entries: fresh).composedText
                if !composed.isEmpty {
                    if let existing {
                        existing.text =
                            hasText
                            ? existing.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + composed
                            : composed
                        existing.updatedAt = importedAt
                    } else {
                        modelContext.insert(
                            DailyEntry(
                                dateKey: day.dateKey.string, originalTimeZoneID: timeZone.identifier, text: composed,
                                createdAt: importedAt, updatedAt: importedAt))
                    }
                }
                for entry in fresh {
                    modelContext.insert(
                        ImportRecord(
                            sourceIdentityHash: entry.identityHash, importedAt: importedAt,
                            sourceArchiveHash: plan.archiveHash, targetDateKey: day.dateKey.string,
                            sourceTitle: entry.title, sourceTimestamp: nil, sectionIndex: entry.sectionIndex))
                }
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        guard !changedDays.isEmpty else { return StoreEffect() }
        return try commit(candidateDays: changedDays, before: before, bumpDays: changedDays)
    }
}
