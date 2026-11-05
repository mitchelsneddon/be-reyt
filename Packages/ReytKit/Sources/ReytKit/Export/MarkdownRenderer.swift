import Foundation

/// Renders a `ReadableJournal` as Markdown: `index.md`, one `YYYY-MM-DD.md` per day with content, and
/// `weekly-reviews.md` when any week has a "more of this" note. Pure and deterministic: the same input gives
/// byte-identical output.
public enum MarkdownRenderer {
    public struct File: Sendable, Equatable {
        public var path: String
        public var contents: String
    }

    public static let indexName = "index.md"
    public static let reviewsName = "weekly-reviews.md"
    public static let workoutsNote = "workouts copied from apple health"

    public static func render(_ journal: ReadableJournal) -> [File] {
        var files: [File] = [File(path: indexName, contents: index(journal))]
        files += journal.days.map { File(path: "\($0.key.string).md", contents: day($0)) }
        if !journal.weeks.isEmpty { files.append(File(path: reviewsName, contents: reviews(journal.weeks))) }
        return files
    }

    public static func render(_ data: ArchiveData, includeWorkouts: Bool, range: ClosedRange<DateKey>? = nil) -> [File]
    {
        render(ReadableJournal(data, includeWorkouts: includeWorkouts, range: range))
    }

    // MARK: Pieces

    static func index(_ journal: ReadableJournal) -> String {
        var out = "# be reyt journal\n\n"
        out +=
            journal.includeWorkouts
            ? "workouts are included, copied from apple health.\n" : "workouts are not included.\n"
        out += "\nthis is a readable export. it isn't encrypted, so keep it somewhere private.\n"
        guard let first = journal.days.first, let last = journal.days.last else {
            return out + "\nno days to show.\n"
        }
        out += "\n\(journal.days.count) \(journal.days.count == 1 ? "day" : "days"), "
        out += "\(ReadableFormat.shortDate(first.key)) to \(ReadableFormat.shortDate(last.key)).\n"
        var month: (Int, Int)?
        for d in journal.days {
            if month?.0 != d.key.year || month?.1 != d.key.month {
                month = (d.key.year, d.key.month)
                out += "\n## \(ReadableFormat.monthTitle(year: d.key.year, month: d.key.month))\n\n"
            }
            out += "- [\(d.heading)](\(d.key.string).md)\n"
        }
        if !journal.weeks.isEmpty { out += "\n## weekly reviews\n\n- [more of this notes](\(reviewsName))\n" }
        return out
    }

    static func day(_ d: ReadableDay) -> String {
        var blocks: [String] = ["# \(d.heading)"]
        var meta: [String] = []
        if let score = d.scoreLabel { meta.append("day score: \(score)") }
        if !d.moods.isEmpty { meta.append("moods: \(d.moods.joined(separator: ", "))") }
        if !d.tags.isEmpty { meta.append("tags: \(d.tags.joined(separator: ", "))") }
        if !meta.isEmpty { blocks.append(meta.joined(separator: "  \n")) }
        if let text = d.text { blocks.append(body(text)) }
        for a in d.answers { blocks.append("## \(heading(a.title))\n\n\(body(a.body))") }
        if let plan = d.plan {
            var section = "## \(ReadableFormat.planTitle)"
            if let label = plan.categoryLabel { section += "\n\n\(label)" }
            if let text = ReadableFormat.nonblank(plan.text) { section += "\n\n\(body(text))" }
            blocks.append(section)
        }
        if let f = d.followUp {
            var section = "## \(ReadableFormat.followUpTitle)"
            if let plan = f.plan { section += "\n\nyou planned: \(inline(plan))" }
            section += "\n\n\(body(f.note))"
            blocks.append(section)
        }
        if !d.photos.isEmpty {
            let links = d.photos.enumerated().map { "![photo \($0.offset + 1)](photos/\($0.element.fileName))" }
            blocks.append("## photos\n\n" + links.joined(separator: "\n\n"))
        }
        if !d.workouts.isEmpty {
            blocks.append(
                "## workouts\n\n\(workoutsNote)\n\n" + d.workouts.map { "- \(inline($0))" }.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func reviews(_ weeks: [ReadableWeek]) -> String {
        var blocks = ["# weekly reviews"]
        for w in weeks {
            blocks.append(
                "## \(ReadableFormat.shortDate(w.weekStart)) to \(ReadableFormat.shortDate(w.weekEnd))\n\nmore of this: \(inline(w.moreOfThis))"
            )
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: Escaping

    /// Multi-line user text with each line's leading Markdown markers neutralised (see `escapeLine`) and a hard
    /// line break between consecutive non-empty lines, so a line break in the journal stays a line break.
    static func body(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        for (i, line) in lines.enumerated() {
            let escaped = escapeLine(line)
            let nextHasText = i + 1 < lines.count && !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty
            let breaks = !line.trimmingCharacters(in: .whitespaces).isEmpty && nextHasText
            out.append(breaks ? escaped + "  " : escaped)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// Single-line user text (a heading or list item): newlines collapse to spaces, leading markers escaped.
    static func inline(_ text: String) -> String {
        escapeLine(text.components(separatedBy: .newlines).joined(separator: " "))
    }

    static func heading(_ text: String) -> String { inline(text) }

    /// A line starting with `#`, `>` or a code fence would change meaning, so it gets a leading backslash.
    /// Everything else is verbatim (Unicode, emoji and right-to-left text are untouched).
    static func escapeLine(_ line: String) -> String {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first else { return line }
        if first == "#" || first == ">" || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return "\\" + line
        }
        return line
    }
}
