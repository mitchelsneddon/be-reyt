import CryptoKit
import Foundation

public enum AppleJournalDateSource: Sendable, Equatable {
    /// The `pageHeader` date, the entry's real date.
    case header
    /// The header could not be read; the filename date minus one day (the export names files a day late).
    case filenameFallback
}

/// One entry of an Apple Journal export, parsed at the boundary into plain values (A6).
public struct AppleJournalEntry: Sendable, Equatable {
    /// Path of the entry file relative to the export folder, e.g. `Entries/2026-10-27_Oct_27th.html`.
    public let relativePath: String
    public let dateKey: DateKey
    public let dateSource: AppleJournalDateSource
    /// The header text as exported, e.g. "Monday, October 26, 2026".
    public let headerText: String
    /// The title as exported (kept as source metadata); nil when blank.
    public let title: String?
    public let body: String
    /// Photo files, relative to the export folder, already validated as safe, present and image-like.
    public let photos: [String]
    /// Short descriptions of attachments that were left out.
    public let unsupported: [String]
    public let identityHash: String
    /// Position among the entries of the same day, in filename (chronological) order.
    public internal(set) var sectionIndex: Int

    public var fileName: String { String(relativePath.split(separator: "/").last ?? "") }

    /// The title worth showing inside the text: custom titles only, never the automatic date title.
    public var sectionTitle: String? {
        guard let title, !AppleJournalParser.isAutomaticTitle(title, headerText: headerText) else { return nil }
        return title
    }

    /// "{title}\n\n{body}", or just the body when there is no custom title; empty when there is neither.
    public var sectionText: String {
        switch (sectionTitle, body.isEmpty) {
        case (nil, _): body
        case (let t?, true): t
        case (let t?, false): "\(t)\n\n\(body)"
        }
    }
}

/// All new entries that land on one calendar day, oldest first. They become sections of one page.
public struct AppleJournalDay: Sendable, Equatable {
    public let dateKey: DateKey
    public let entries: [AppleJournalEntry]

    /// Sections separated by a blank line; sections with nothing in them are left out.
    public var composedText: String {
        entries.map(\.sectionText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

public struct AppleJournalUnsupportedItem: Sendable, Equatable {
    public let entryPath: String
    public let description: String
}

public struct AppleJournalParseFailure: Sendable, Equatable {
    public enum Reason: Error, Sendable, Equatable {
        case notAnEntry
        case unreadable
        case tooLarge
        case symbolicLink
        case noDate
    }
    public let path: String
    public let reason: Reason
}

/// What the user is shown before anything is written, and what the store commits.
public struct AppleJournalImportPlan: Sendable, Equatable {
    /// The export folder the plan was read from (photos are read from here after the text is committed).
    public let root: URL
    /// New entries only, ordered by day then filename.
    public let entries: [AppleJournalEntry]
    /// Entries already imported earlier; they are skipped.
    public let duplicates: [AppleJournalEntry]
    public let days: [AppleJournalDay]
    /// Days that already hold text. The user chooses append or skip for each.
    public let conflicts: [DateKey]
    public let unsupported: [AppleJournalUnsupportedItem]
    public let failures: [AppleJournalParseFailure]
    public let archiveHash: String

    public var photoCount: Int { entries.reduce(0) { $0 + $1.photos.count } }
    public var dateRange: ClosedRange<DateKey>? {
        guard let first = days.first?.dateKey, let last = days.last?.dateKey else { return nil }
        return first...last
    }
    public var fallbackDateCount: Int { entries.filter { $0.dateSource == .filenameFallback }.count }
    public var isEmpty: Bool { entries.isEmpty }
}

public enum AppleJournalConflictResolution: Sendable, Equatable {
    /// Imported sections go after what is already on the page, separated by a blank line.
    case append
    /// Leave that day alone.
    case skip
}

enum AppleJournalHashing {
    static func hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
