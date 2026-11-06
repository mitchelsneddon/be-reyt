import Foundation
import SwiftData

/// History reads: which days have content, and which of them match a search. Read-only.
extension JournalStore {
    /// Every day whose `DayContent.hasUserContent` is true, newest first. A day with only a prompt assignment,
    /// or only workouts, never appears.
    public func historyDays() throws -> [DaySummary] {
        // shortcut: loads every entry, attachment and intention then groups in memory; fine for a personal
        // journal (a few thousand days), move to per-month fetches past ~20k days.
        var parts: [DateKey: DaySummary] = [:]
        func edit(_ key: DateKey, _ body: (inout DaySummary) -> Void) {
            var summary = parts[key] ?? DaySummary(dateKey: key, content: DayContent())
            body(&summary)
            parts[key] = summary
        }

        for e in try modelContext.fetch(FetchDescriptor<DailyEntry>()) {
            guard let key = DateKey(e.dateKey) else { continue }
            edit(key) {
                $0.content.text = e.text
                $0.content.smileAnswer = e.smileAnswer
                $0.content.rotatingAnswer = e.rotatingAnswer
                $0.content.dayScore = e.dayScore
                $0.content.moodIDs = e.moodIDs
            }
        }
        for a in try modelContext.fetch(FetchDescriptor<Attachment>()) {
            guard let key = DateKey(a.entryDateKey) else { continue }
            edit(key) { $0.content.attachmentCount += 1 }
        }
        for row in try modelContext.fetch(FetchDescriptor<WeeklyIntention>()) {
            if let key = DateKey(row.sourceSundayKey),
                DayContent.isNonblank(row.text) || DayContent.isNonblank(row.category)
            {
                edit(key) {
                    $0.content.hasIntention = true
                    $0.planText = DayContent.isNonblank(row.text) ? row.text : nil
                }
            }
            if let key = row.followUpWrittenOnKey.flatMap(DateKey.init), let note = row.followUpNote,
                DayContent.isNonblank(note)
            {
                edit(key) {
                    $0.content.hasFollowUpNote = true
                    $0.followUpNote = [$0.followUpNote, note].compactMap { $0 }.joined(separator: "\n")
                }
            }
        }
        return parts.values.filter { $0.content.hasUserContent }.sorted { $0.dateKey > $1.dateKey }
    }

    /// Days matching `text` in the entry text, smile answer, rotating answer, Sunday plan or follow-up note
    /// (case and diacritic insensitive). Newest first. Blank text returns every day with content.
    public func searchDays(text: String) throws -> [DateKey] {
        // shortcut: filters in memory after `historyDays()`, because localizedStandardContains has no #Predicate
        // form; fine at the same scale (a few thousand days).
        try historyDays()
            .filter { $0.matches(text: text) }
            .map(\.dateKey)
    }
}
