import Foundation

public enum MoodCatalog {
    public struct Mood: Hashable, Sendable {
        public let id: String
        public let label: String
    }

    /// What a new day can pick. Order is display order. IDs are stable and persisted; labels are display only.
    public static let active: [Mood] = [
        Mood(id: "happy", label: "happy"),
        Mood(id: "sad", label: "sad"),
        Mood(id: "stressed", label: "stressed"),
        Mood(id: "annoyed", label: "annoyed"),
        Mood(id: "anxious", label: "anxious"),
    ]

    /// No longer offered, but still stored on older days, so it must keep resolving, counting and exporting.
    public static let retired: [Mood] = [
        Mood(id: "tired", label: "tired")
    ]

    public static let all: [Mood] = active + retired

    /// The moods a picker shows: every active mood, then any retired mood the day already carries.
    public static func offered(including selected: [String]) -> [Mood] {
        active + retired.filter { selected.contains($0.id) }
    }

    public static func isRetired(_ id: String) -> Bool { retired.contains { $0.id == id } }

    public static func label(for id: String) -> String? { all.first { $0.id == id }?.label }

    /// Dedupes; known IDs first in catalog order; unknown IDs kept (never dropped) in first-seen order.
    public static func normalize(_ ids: [String]) -> [String] {
        let given = Set(ids)
        let known = all.map(\.id).filter(given.contains)
        var seen = Set(known)
        var unknown: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            unknown.append(id)
        }
        return known + unknown
    }
}
