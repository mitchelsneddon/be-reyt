import Foundation

public enum MoodCatalog {
    public struct Mood: Hashable, Sendable {
        public let id: String
        public let label: String
    }

    /// Catalog order is display order. IDs are stable and persisted; labels are display only.
    public static let all: [Mood] = [
        Mood(id: "happy", label: "happy"),
        Mood(id: "stressed", label: "stressed"),
        Mood(id: "tired", label: "tired"),
        Mood(id: "annoyed", label: "annoyed"),
    ]

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
