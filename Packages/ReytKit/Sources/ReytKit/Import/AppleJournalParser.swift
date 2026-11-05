import Foundation

public enum AppleJournalParseError: Error, Equatable, Sendable {
    /// No `Entries` folder in the chosen folder (the user may have picked the zip, or the wrong folder).
    case noEntriesFolder
    case unsafeFolder
    case tooManyFiles
    case tooLarge
    case cancelled
}

/// Reads an unzipped Apple Journal export (the `AppleJournalEntries` folder) into an `AppleJournalImportPlan`.
///
/// Only the folder form is supported; the user is told to unzip first. Pure Foundation file reads: no WebKit,
/// no attributed-string HTML import, nothing evaluated or fetched. Only `Entries/*.html` is read, plus the
/// `Resources/` files an entry's asset grid points at, after path, symlink, size and type checks (P3).
public enum AppleJournalParser {
    public struct Limits: Sendable {
        public var maxFiles = 20_000
        public var maxHTMLBytes = 20 * 1024 * 1024
        public var maxMediaBytes = 200 * 1024 * 1024
        public var maxTotalHTMLBytes = 512 * 1024 * 1024
        public var maxTotalMediaBytes = 4 * 1024 * 1024 * 1024
        public init() {}
    }

    /// Parses `folder`. `existingHashes` are identity hashes already imported; `daysWithText` are days that
    /// already hold written text. `progress` receives (done, total) per entry file.
    public static func parse(
        folder: URL, existingHashes: Set<String>, daysWithText: Set<DateKey>, limits: Limits = Limits(),
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> AppleJournalImportPlan {
        let root = try resolveRoot(folder)
        let realRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let entriesDir = root.appending(path: "Entries", directoryHint: .isDirectory)

        let names = try FileManager.default.contentsOfDirectory(
            at: entriesDir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        )
        guard names.count <= limits.maxFiles else { throw AppleJournalParseError.tooManyFiles }

        var failures: [AppleJournalParseFailure] = []
        var candidates: [URL] = []
        for url in names.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if values?.isSymbolicLink == true {
                failures.append(.init(path: "Entries/\(url.lastPathComponent)", reason: .symbolicLink))
            } else if values?.isRegularFile == true, url.pathExtension.lowercased() == "html" {
                candidates.append(url)
            }
        }

        var media = MediaChecker(root: root, realRoot: realRoot, limits: limits)
        var parsed: [AppleJournalEntry] = []
        var unsupported: [AppleJournalUnsupportedItem] = []
        var totalHTML = 0
        for (index, url) in candidates.enumerated() {
            progress?(index, candidates.count)
            let relative = "Entries/\(url.lastPathComponent)"
            guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(realRoot + "/") else {
                failures.append(.init(path: relative, reason: .unsafeFolderReason))
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
            guard size <= limits.maxHTMLBytes else {
                failures.append(.init(path: relative, reason: .tooLarge))
                continue
            }
            totalHTML += size
            guard totalHTML <= limits.maxTotalHTMLBytes else { throw AppleJournalParseError.tooLarge }
            guard let data = try? Data(contentsOf: url) else {
                failures.append(.init(path: relative, reason: .unreadable))
                continue
            }
            switch parseEntry(bytes: [UInt8](data), relativePath: relative, media: &media) {
            case .success(let entry):
                parsed.append(entry)
                unsupported += entry.unsupported.map { .init(entryPath: relative, description: $0) }
            case .failure(let reason):
                failures.append(.init(path: relative, reason: reason))
            }
        }
        progress?(candidates.count, candidates.count)
        return buildPlan(
            root: root, parsed: parsed, unsupported: unsupported, failures: failures,
            existingHashes: existingHashes, daysWithText: daysWithText)
    }

    // MARK: Folder

    private static func resolveRoot(_ folder: URL) throws -> URL {
        func hasEntries(_ dir: URL) -> Bool {
            let e = dir.appending(path: "Entries", directoryHint: .isDirectory)
            let v = try? e.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return v?.isDirectory == true && v?.isSymbolicLink != true
        }
        if hasEntries(folder) { return folder }
        // A zip often unpacks to one wrapper folder.
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        let nested = children.filter {
            let v = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return v?.isDirectory == true && v?.isSymbolicLink != true && hasEntries($0)
        }
        if nested.count == 1, let only = nested.first { return only }
        let entries = folder.appending(path: "Entries", directoryHint: .isDirectory)
        if (try? entries.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw AppleJournalParseError.unsafeFolder
        }
        throw AppleJournalParseError.noEntriesFolder
    }

    // MARK: Plan

    private static func buildPlan(
        root: URL, parsed: [AppleJournalEntry], unsupported: [AppleJournalUnsupportedItem],
        failures: [AppleJournalParseFailure], existingHashes: Set<String>, daysWithText: Set<DateKey>
    ) -> AppleJournalImportPlan {
        // Same-day order: filename (the export names files by date, so this is chronological enough).
        var seenHashes = Set<String>()
        let ordered = parsed.sorted {
            ($0.dateKey, $0.relativePath) < ($1.dateKey, $1.relativePath)
        }.filter { seenHashes.insert($0.identityHash).inserted }

        var indexed: [AppleJournalEntry] = []
        var perDay: [DateKey: Int] = [:]
        for var entry in ordered {
            let n = perDay[entry.dateKey, default: 0]
            entry.sectionIndex = n
            perDay[entry.dateKey] = n + 1
            indexed.append(entry)
        }
        let fresh = indexed.filter { !existingHashes.contains($0.identityHash) }
        let duplicates = indexed.filter { existingHashes.contains($0.identityHash) }
        var grouped: [DateKey: [AppleJournalEntry]] = [:]
        for e in fresh { grouped[e.dateKey, default: []].append(e) }
        let days = grouped.keys.sorted().map { AppleJournalDay(dateKey: $0, entries: grouped[$0] ?? []) }
        let freshPaths = Set(fresh.map(\.relativePath))
        return AppleJournalImportPlan(
            root: root, entries: fresh, duplicates: duplicates, days: days,
            conflicts: days.map(\.dateKey).filter { daysWithText.contains($0) },
            unsupported: unsupported.filter { freshPaths.contains($0.entryPath) },
            failures: failures,
            archiveHash: AppleJournalHashing.hex(indexed.map(\.identityHash).sorted().joined(separator: "\n")))
    }

    // MARK: Entry

    private enum Region { case none, header, assets, title, body }

    private static func parseEntry(
        bytes: [UInt8], relativePath: String, media: inout MediaChecker
    ) -> Result<AppleJournalEntry, AppleJournalParseFailure.Reason> {
        var region = Region.none
        var depth = 0
        var seenMarker = false
        var header = ""
        var title = ""
        var body = BodyBuilder()
        var photos: [String] = []
        var unsupported: [String] = []
        var assetTextSeen = false
        var videoDepth = 0

        func start(_ r: Region) {
            region = r
            depth = 1
            seenMarker = true
        }

        for token in HTMLScanner.tokens(bytes) {
            switch token {
            case .open(let name, let attrs):
                if name == "div" {
                    let classes = Set((attrs["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
                    if classes.contains("pageHeader") {
                        start(.header)
                        continue
                    } else if classes.contains("assetGrid") {
                        start(.assets)
                        continue
                    } else if classes.contains("title") {
                        start(.title)
                        continue
                    } else if classes.contains("bodyText") {
                        region = .body
                        seenMarker = true
                        body.blockBoundary()
                        continue
                    }
                }
                switch region {
                case .header, .title:
                    if name == "div" { depth += 1 }
                case .assets:
                    if name == "div" {
                        depth += 1
                    } else {
                        classifyAsset(
                            name: name, attrs: attrs, entryPath: relativePath, media: &media, photos: &photos,
                            unsupported: &unsupported, videoDepth: &videoDepth)
                    }
                case .body:
                    body.open(name)
                case .none:
                    break
                }
            case .close(let name):
                switch region {
                case .header, .title, .assets:
                    if name == "div" {
                        depth -= 1
                        if depth <= 0 { region = .none }
                    } else if name == "video" || name == "audio" {
                        videoDepth = max(0, videoDepth - 1)
                    }
                case .body: body.close(name)
                case .none: break
                }
            case .text(let text):
                switch region {
                case .header: header += text
                case .title: title += text
                case .assets:
                    if !text.allSatisfy({ $0.isWhitespace || $0 == "\u{00A0}" }), !assetTextSeen, videoDepth == 0 {
                        assetTextSeen = true
                        unsupported.append("other attachment ignored")
                    }
                case .body: body.text(text)
                case .none: break
                }
            }
        }
        guard seenMarker else { return .failure(.notAnEntry) }

        let headerText = collapse(header)
        let fileName = String(relativePath.split(separator: "/").last ?? "")
        let date: DateKey
        let source: AppleJournalDateSource
        if let parsedDate = parseHeaderDate(headerText) {
            (date, source) = (parsedDate, .header)
        } else if let named = DateKey(String(fileName.prefix(10))) {
            (date, source) = (named.adding(days: -1), .filenameFallback)
        } else {
            return .failure(.noDate)
        }
        let cleanTitle = collapse(title)
        let bodyText = body.finish()
        let identity = AppleJournalHashing.hex(
            [relativePath, headerText, cleanTitle, bodyText].joined(separator: "\u{1F}"))
        return .success(
            AppleJournalEntry(
                relativePath: relativePath, dateKey: date, dateSource: source, headerText: headerText,
                title: cleanTitle.isEmpty ? nil : cleanTitle, body: bodyText, photos: photos,
                unsupported: unsupported, identityHash: identity, sectionIndex: 0))
    }

    private static func classifyAsset(
        name: String, attrs: [String: String], entryPath: String, media: inout MediaChecker, photos: inout [String],
        unsupported: inout [String], videoDepth: inout Int
    ) {
        switch name {
        case "img":
            guard videoDepth == 0 else { return }
            switch media.check(src: attrs["src"] ?? "") {
            case .photo(let path): if !photos.contains(path) { photos.append(path) }
            case .rejected(let why): unsupported.append(why)
            }
        case "video", "audio":
            videoDepth += 1
            unsupported.append("\(name) attachment ignored")
        case "a": unsupported.append("link ignored")
        case "iframe", "embed", "object": unsupported.append("embedded content ignored")
        case "source", "track", "span", "br", "p", "figure", "figcaption": break
        default: break
        }
    }

    // MARK: Dates and titles

    private static let months: [String: Int] = {
        let names = [
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
            "november", "december",
        ]
        var map: [String: Int] = [:]
        for (i, n) in names.enumerated() {
            map[n] = i + 1
            map[String(n.prefix(3))] = i + 1
        }
        map["sept"] = 9
        return map
    }()

    /// "Monday, October 26, 2026" or "October 26, 2026" (English month names, any order of the day and month).
    /// Builds the civil day directly (A4), no calendar or locale involved.
    static func parseHeaderDate(_ text: String) -> DateKey? {
        let words = text.split { !$0.isLetter && !$0.isNumber }.map { String($0).lowercased() }
        var month: Int?
        var day: Int?
        var year: Int?
        for w in words {
            if month == nil, let m = months[w] {
                month = m
            } else if w.allSatisfy(\.isNumber), let n = Int(w) {
                if w.count == 4 { year = year ?? n } else if (1...31).contains(n) { day = day ?? n }
            }
        }
        guard let month, let day, let year else { return nil }
        return DateKey(year: year, month: month, day: day)
    }

    /// True for the titles Journal makes up itself: "Oct 26th", "October 26", or the header date.
    public static func isAutomaticTitle(_ title: String, headerText: String) -> Bool {
        let t = collapse(title)
        if t.isEmpty || t == collapse(headerText) { return true }
        let parts = t.split(separator: " ").map(String.init)
        guard parts.count == 2, parts[0].allSatisfy({ $0.isLetter || $0 == "." }),
            months[parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))] != nil
        else { return parseHeaderDate(t) != nil }
        let digits = parts[1].prefix { $0.isNumber }
        let suffix = parts[1].dropFirst(digits.count).lowercased()
        guard let n = Int(digits), (1...31).contains(n) else { return false }
        return ["", "st", "nd", "rd", "th"].contains(suffix)
    }

    static func collapse(_ s: String) -> String {
        var out = ""
        var pendingSpace = false
        for ch in s {
            if ch.isWhitespace || ch == "\u{00A0}" {
                pendingSpace = !out.isEmpty
            } else {
                if pendingSpace { out.append(" ") }
                pendingSpace = false
                out.append(ch)
            }
        }
        return out
    }
}

extension AppleJournalParseFailure.Reason {
    /// A file that resolves outside the export folder is treated like a symlink.
    fileprivate static var unsafeFolderReason: Self { .symbolicLink }
}

/// Builds the body text from the block structure. Paragraphs end at `<p>`, `</p>` and block tags; a paragraph of
/// only `<br>` is a blank line; whitespace inside a paragraph collapses to single spaces.
private struct BodyBuilder {
    private var paragraphs: [String] = []
    private var lines: [String] = []
    private var current = ""
    private var sawBreak = false
    private var bullet = false

    private static let blocks: Set<String> = [
        "p", "div", "ul", "ol", "li", "blockquote", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "table",
    ]

    mutating func open(_ name: String) {
        if name == "br" {
            lines.append(current)
            current = ""
            sawBreak = true
        } else if Self.blocks.contains(name) {
            blockBoundary()
            if name == "li" { bullet = true }
        }
    }

    mutating func close(_ name: String) {
        if Self.blocks.contains(name) { blockBoundary() }
    }

    mutating func text(_ s: String) { current += s }

    mutating func blockBoundary() {
        lines.append(current)
        var cleaned = lines.map(AppleJournalParser.collapse)
        let hadText = cleaned.contains { !$0.isEmpty }
        if hadText {
            while cleaned.last == "" { cleaned.removeLast() }
            while cleaned.first == "" { cleaned.removeFirst() }
            if bullet, !cleaned.isEmpty { cleaned[0] = "\u{2022} " + cleaned[0] }
            paragraphs.append(cleaned.joined(separator: "\n"))
        } else if sawBreak {
            paragraphs.append("")
        }
        lines = []
        current = ""
        sawBreak = false
        bullet = false
    }

    mutating func finish() -> String {
        blockBoundary()
        return paragraphs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Validates the media an entry points at, and keeps the running size budget.
private struct MediaChecker {
    enum Outcome {
        case photo(String)
        case rejected(String)
    }

    let root: URL
    let realRoot: String
    let limits: AppleJournalParser.Limits
    private var counted: [String: Int] = [:]
    private var total = 0

    init(root: URL, realRoot: String, limits: AppleJournalParser.Limits) {
        self.root = root
        self.realRoot = realRoot
        self.limits = limits
    }

    /// `src` is relative to the entry file, which lives in `Entries/`.
    mutating func check(src: String) -> Outcome {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .rejected("photo with no file ignored") }
        // Anything with a scheme or a network-path prefix is remote or otherwise not a file in the export.
        let beforeSlash = trimmed.prefix { $0 != "/" }
        if trimmed.hasPrefix("/") || beforeSlash.contains(":") { return .rejected("remote resource ignored") }
        guard let decoded = trimmed.removingPercentEncoding, let path = Self.normalise(decoded, base: "Entries"),
            Paths.isSafeRelativePath(path)
        else { return .rejected("photo outside the export ignored") }
        guard path.hasPrefix("Resources/") else { return .rejected("file outside the resources folder ignored") }

        let url = path.split(separator: "/").reduce(root) {
            $0.appending(path: String($1), directoryHint: .notDirectory)
        }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard let values, values.isRegularFile == true else { return .rejected("photo file is missing") }
        guard values.isSymbolicLink != true,
            url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(realRoot + "/")
        else { return .rejected("linked file ignored") }
        let size = values.fileSize ?? Int.max
        guard size <= limits.maxMediaBytes else { return .rejected("photo is too large to import") }
        if counted[path] == nil {
            guard total + size <= limits.maxTotalMediaBytes else {
                return .rejected("photo skipped, the export is too large")
            }
            counted[path] = size
            total += size
        }
        guard Self.looksLikeImage(url) else { return .rejected("not a supported image, ignored") }
        return .photo(path)
    }

    /// Joins `src` onto `base`, resolving `.` and `..`; nil when it climbs out of the export folder.
    static func normalise(_ src: String, base: String) -> String? {
        var parts = base.split(separator: "/").map(String.init)
        for component in src.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch component {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(component)
            }
        }
        return parts.joined(separator: "/")
    }

    /// Magic numbers of the image types be reyt keeps. The app still decodes the bytes before storing.
    private static func looksLikeImage(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16), head.count >= 12 else { return false }
        let b = [UInt8](head)
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return true }  // jpeg
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return true }  // png
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38 { return true }  // gif
        if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0)
            || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0 && b[3] == 0x2A)
        {
            return true  // tiff
        }
        let tag = String(decoding: b[4..<8], as: UTF8.self)
        if tag == "ftyp" {  // heic / heif
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            return ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1", "heif"].contains(brand)
        }
        if String(decoding: b[0..<4], as: UTF8.self) == "RIFF", String(decoding: b[8..<12], as: UTF8.self) == "WEBP" {
            return true
        }
        return false
    }
}
