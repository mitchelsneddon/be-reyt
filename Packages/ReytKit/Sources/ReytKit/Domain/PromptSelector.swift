import Foundation

/// Chooses the rotating prompt for a day. A pure function of the day, the assignment history and the catalog:
/// no randomness, no `Hasher`, so the same inputs give the same answer on every launch.
///
/// Candidates are prompts not assigned within `window` days of the day, in either direction (so backfilling a
/// skipped day cannot repeat a later day's prompt). They are ordered least-recently-used first (never used
/// counts as oldest), ties broken by a fixed seeded order. If the window leaves nothing, every prompt is
/// ordered the same way and the least recently used wins.
public struct PromptSelector: Sendable {
    public static let window = 14
    static let seed: UInt64 = 0x5EED_BE17_E417_0001

    private let catalog: [PromptChoice]
    private let tieBreak: [String: UInt64]

    public init(catalog: [PromptChoice] = PromptCatalog.all) {
        self.catalog = catalog
        self.tieBreak = Dictionary(
            catalog.map { ($0.id, Self.splitMix64(Self.fnv1a($0.id) ^ Self.seed)) }, uniquingKeysWith: { a, _ in a })
    }

    /// The prompt for a day with no assignment.
    public func select(for key: DateKey, history: [PromptHistoryItem]) -> PromptChoice {
        ordered(for: key, history: history)[0]
    }

    /// "Another prompt": the next one in the same ordering after the current prompt, wrapping around.
    /// The day's own assignment never counts as history, so it cannot block or age itself.
    public func reroll(for key: DateKey, current: String?, history: [PromptHistoryItem]) -> PromptChoice {
        let order = ordered(for: key, history: history)
        guard let current, let i = order.firstIndex(where: { $0.id == current }) else {
            return order.first { $0.id != current } ?? order[0]
        }
        return order[(i + 1) % order.count]
    }

    private func ordered(for key: DateKey, history: [PromptHistoryItem]) -> [PromptChoice] {
        let others = history.filter { $0.dateKey != key }
        var lastUsed: [String: Int] = [:]
        var blocked = Set<String>()
        for item in others {
            let day = item.dateKey.epochDay
            lastUsed[item.promptID] = max(lastUsed[item.promptID] ?? Int.min, day)
            if abs(day - key.epochDay) <= Self.window { blocked.insert(item.promptID) }
        }
        func sorted(_ prompts: [PromptChoice]) -> [PromptChoice] {
            prompts.sorted { a, b in
                let la = lastUsed[a.id] ?? Int.min
                let lb = lastUsed[b.id] ?? Int.min
                if la != lb { return la < lb }
                let ta = tieBreak[a.id] ?? 0
                let tb = tieBreak[b.id] ?? 0
                return ta != tb ? ta < tb : a.id < b.id
            }
        }
        let candidates = catalog.filter { !blocked.contains($0.id) }
        return sorted(candidates.isEmpty ? catalog : candidates)
    }

    // MARK: Stable hashing

    /// FNV-1a over the UTF-8 bytes: the same on every launch, unlike Swift's per-process `Hasher`.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func splitMix64(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
