import Foundation

/// What a `JournalStore` mutation changed, so the app can fan out side effects (reminders, backup dirtiness).
public struct StoreEffect: Sendable, Equatable {
    /// Days whose `DayContent.hasUserContent` flipped.
    public var contentChangedDays: Set<DateKey>
    /// Week starts whose generated narrative was purged because the model input changed.
    public var revisionBumpedWeeks: Set<DateKey>
    /// Anything persisted changed (the backup is stale).
    public var dirty: Bool

    public init(
        contentChangedDays: Set<DateKey> = [], revisionBumpedWeeks: Set<DateKey> = [], dirty: Bool = false
    ) {
        self.contentChangedDays = contentChangedDays
        self.revisionBumpedWeeks = revisionBumpedWeeks
        self.dirty = dirty
    }

    public var isEmpty: Bool { self == StoreEffect() }

    public mutating func merge(_ other: StoreEffect) {
        contentChangedDays.formUnion(other.contentChangedDays)
        revisionBumpedWeeks.formUnion(other.revisionBumpedWeeks)
        dirty = dirty || other.dirty
    }
}
