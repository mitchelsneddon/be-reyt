import Foundation

/// One day that has content, with the text the history list and search need. Built by `JournalStore`; `content`
/// is the same `DayContent` the rest of the app uses, so history agrees with reminders and coverage (A3).
public struct DaySummary: Sendable, Equatable, Identifiable {
    public var dateKey: DateKey
    public var content: DayContent
    /// The Sunday plan sourced on this day, when nonblank.
    public var planText: String?
    /// Follow-up notes written on this day, joined by a newline, when nonblank.
    public var followUpNote: String?

    public var id: DateKey { dateKey }

    public init(dateKey: DateKey, content: DayContent, planText: String? = nil, followUpNote: String? = nil) {
        self.dateKey = dateKey
        self.content = content
        self.planText = planText
        self.followUpNote = followUpNote
    }

    /// Every text field search looks at, in the order the list prefers them for its preview line.
    var searchableFields: [String] {
        [content.text, content.smileAnswer, content.rotatingAnswer, planText, followUpNote].compactMap { $0 }
    }

    /// First nonblank line of the entry text, else of the smile answer, rotating answer, plan or follow-up note.
    public var preview: String {
        for field in searchableFields {
            let line = field.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            if let line { return line }
        }
        return ""
    }

    /// Case- and diacritic-insensitive: "cafe" matches "Café". A blank query matches everything.
    public func matches(text query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        return searchableFields.contains { $0.localizedStandardContains(needle) }
    }
}
