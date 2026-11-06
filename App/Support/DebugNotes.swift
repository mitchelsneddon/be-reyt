#if DEBUG
    import Foundation

    /// Simulator-only: `-showRestoreNote restored|undone` and `-showDeleteAllNote done|partial` show the real banners.
    enum DebugNotes {
        @MainActor static func apply(restore: RestoreCoordinator, deleteAll: DeleteAllCoordinator) {
            let args = CommandLine.arguments
            if let value = value(after: "-showRestoreNote", in: args) {
                restore.debugShowNote(undone: value == "undone")
            }
            if let value = value(after: "-showDeleteAllNote", in: args) {
                deleteAll.debugShowNote(partial: value == "partial")
            }
        }

        private static func value(after flag: String, in args: [String]) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
    }
#endif
