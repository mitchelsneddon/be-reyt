import Foundation
import Observation
import ReytKit

/// Rename and delete for the tags screen. Every write goes through `JournalStore`; effects go to `JournalEvents`.
@MainActor @Observable
final class TagsModel {
    enum RenameResult: Equatable {
        case renamed, blank, taken, failed
    }

    @ObservationIgnored private let store: JournalStore
    @ObservationIgnored private let events: JournalEvents

    init(store: JournalStore, events: JournalEvents) {
        self.store = store
        self.events = events
    }

    func rename(_ id: UUID, to name: String) async -> RenameResult {
        do {
            events.receive(try await store.renameTag(id: id, to: name))
            return .renamed
        } catch JournalStoreError.invalidTagName {
            return .blank
        } catch JournalStoreError.tagNameTaken {
            return .taken
        } catch {
            return .failed
        }
    }

    /// Returns whether the tag was removed.
    func delete(_ id: UUID) async -> Bool {
        do {
            events.receive(try await store.deleteTag(id: id))
            return true
        } catch {
            return false
        }
    }
}
