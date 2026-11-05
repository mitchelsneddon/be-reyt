import Foundation
import SwiftData
import Testing

@testable import ReytKit

/// Synthetic export folders in the Cocoa HTML Writer shape documented in the M1 findings.
private final class Export {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "aj-\(UUID().uuidString)/AppleJournalEntries")
        try FileManager.default.createDirectory(
            at: root.appending(path: "Entries"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Resources"), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    static func page(header: String, title: String, assets: String = "", body: String) -> String {
        """
        <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
        <html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <meta name="Generator" content="Cocoa HTML Writer">
        <style type="text/css">p.p1 {margin: 0} .bodyText { color: red }</style>
        <script>document.write("SCRIPT-LEAK")</script></head>
        <body>
        <div class='pageHeader'>\(header)</div>
        <div class='assetGrid'>\(assets)</div>
        <div class='title'>\(title)</div>
        <div class='bodyText'>
        \(body)
        </div>
        </body></html>
        """
    }

    func write(_ name: String, _ html: String) throws {
        try html.write(to: root.appending(path: "Entries/\(name)"), atomically: true, encoding: .utf8)
    }

    func writeResource(_ name: String, bytes: [UInt8]) throws {
        try Data(bytes).write(to: root.appending(path: "Resources/\(name)"))
    }

    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 0, 0, 0, 0]

    func parse(
        hashes: Set<String> = [], texted: Set<DateKey> = [], limits: AppleJournalParser.Limits = .init()
    ) throws -> AppleJournalImportPlan {
        try AppleJournalParser.parse(folder: root, existingHashes: hashes, daysWithText: texted, limits: limits)
    }
}

private let oct26 = DateKey("2026-10-26")!
private let oct27 = DateKey("2026-10-27")!

private let simpleBody = """
    <p class='p1'><span class='s1'>Went out for coffee<span class="Apple-converted-space">&nbsp;</span>with Zoë &amp; Rémi &#39;today&#39; 😀</span></p>
    <p class='p2'><span class='s1'><br></span></p>
    <p class='p1'><span class='s1'>second   paragraph
    wrapped</span></p>
    """

@Suite("Apple Journal parser")
struct AppleJournalParserTests {
    @Test("header date wins over the filename date; title and body come out with blank lines and decoded text")
    func headerDateAndBody() throws {
        let e = try Export()
        try e.write(
            "2026-10-27_Oct_26th.html",
            Export.page(header: "Monday, October 26, 2026", title: "Coffee &amp; walk", body: simpleBody))
        let plan = try e.parse()
        let entry = try #require(plan.entries.first)
        #expect(entry.dateKey == oct26 && entry.dateSource == .header)
        #expect(entry.title == "Coffee & walk")
        #expect(entry.body == "Went out for coffee with Zoë & Rémi 'today' 😀\n\nsecond paragraph wrapped")
        #expect(plan.failures.isEmpty)
    }

    @Test("script and style content never reaches the text")
    func scriptAndStyleIgnored() throws {
        let e = try Export()
        let body =
            "<p><span>kept</span></p><script>var x = '<p>SCRIPT-LEAK</p>'</script><style>p{x:y}</style><p>also</p>"
        try e.write("2026-10-27_Oct_26th.html", Export.page(header: "Monday, October 26, 2026", title: "T", body: body))
        let entry = try #require(try e.parse().entries.first)
        #expect(entry.body == "kept\nalso")
        #expect(!entry.body.contains("LEAK") && !(entry.title ?? "").contains("LEAK"))
    }

    @Test("malformed nesting: a div inside p and span still yields the text")
    func malformedNesting() throws {
        let e = try Export()
        let body = "<p class='p1'><span class='s1'>before<div>inside</div>after</span></p><p>last</p>"
        try e.write("2026-10-27_Oct_26th.html", Export.page(header: "Monday, October 26, 2026", title: "T", body: body))
        let entry = try #require(try e.parse().entries.first)
        #expect(entry.body == "before\ninside\nafter\nlast")
    }

    @Test("unreadable header falls back to the filename date minus one day, flagged")
    func filenameFallback() throws {
        let e = try Export()
        try e.write("2026-10-27_Oct_26th.html", Export.page(header: "garbled", title: "Oct 26th", body: "<p>hi</p>"))
        let plan = try e.parse()
        let entry = try #require(plan.entries.first)
        #expect(entry.dateKey == oct26 && entry.dateSource == .filenameFallback)
        #expect(plan.fallbackDateCount == 1)
    }

    @Test("two entries on one header date become one day, two sections in filename order; auto titles skipped")
    func sameDayMerge() throws {
        let e = try Export()
        try e.write(
            "2026-10-27_Oct_26th_2.html",
            Export.page(header: "Monday, October 26, 2026", title: "Evening thoughts", body: "<p>late</p>"))
        try e.write(
            "2026-10-27_Oct_26th_1.html",
            Export.page(header: "Monday, October 26, 2026", title: "Oct 26th", body: "<p>early</p>"))
        let plan = try e.parse()
        #expect(plan.days.count == 1)
        let day = try #require(plan.days.first)
        #expect(day.entries.map(\.sectionIndex) == [0, 1])
        #expect(day.entries.map(\.body) == ["early", "late"])
        #expect(day.composedText == "early\n\nEvening thoughts\n\nlate")
    }

    @Test("automatic date titles are recognised, custom ones are not")
    func automaticTitles() {
        for t in ["Oct 26th", "October 26", "Nov 1st", "Mar 3rd", "Monday, October 26, 2026"] {
            #expect(AppleJournalParser.isAutomaticTitle(t, headerText: "Monday, October 26, 2026"), "\(t)")
        }
        for t in ["Oct walk", "Dinner on the 26th", "Mayor 5th"] {
            #expect(!AppleJournalParser.isAutomaticTitle(t, headerText: "Monday, October 26, 2026"), "\(t)")
        }
    }

    @Test("unsafe, remote and unknown assets become unsupported items; a real photo is a candidate")
    func assets() throws {
        let e = try Export()
        try e.writeResource("ok.png", bytes: Export.png)
        try e.writeResource("notimage.heic", bytes: Array("this is plain text, not an image".utf8))
        let assets = """
            <img src="../Resources/ok.png"><img src="../../etc/passwd"><img src="http://example.com/a.jpg">
            <img src="../Resources/missing.png"><img src="../Resources/notimage.heic"><img src="/etc/hosts">
            <img src="file:///etc/hosts"><video src="../Resources/v.mov"></video><a href="https://x.test">x</a>
            """
        try e.write(
            "2026-10-27_Oct_26th.html",
            Export.page(header: "Monday, October 26, 2026", title: "T", assets: assets, body: "<p>x</p>"))
        let plan = try e.parse()
        let entry = try #require(plan.entries.first)
        #expect(entry.photos == ["Resources/ok.png"])
        let reasons = plan.unsupported.map(\.description)
        #expect(reasons.filter { $0 == "remote resource ignored" }.count == 3)  // http, /etc/hosts, file:
        #expect(reasons.contains("photo outside the export ignored"))
        #expect(reasons.contains("photo file is missing"))
        #expect(reasons.contains("not a supported image, ignored"))
        #expect(reasons.contains("video attachment ignored"))
        #expect(reasons.contains("link ignored"))
    }

    @Test("a symlink in Entries is rejected and never read")
    func symlinkRejected() throws {
        let e = try Export()
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID().uuidString).html")
        try Export.page(header: "Monday, October 26, 2026", title: "T", body: "<p>SECRET</p>")
            .write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: e.root.appending(path: "Entries/2026-10-27_link.html"), withDestinationURL: outside)
        let plan = try e.parse()
        #expect(plan.entries.isEmpty)
        #expect(plan.failures.map(\.reason) == [.symbolicLink])
    }

    @Test("a garbage file is reported and the good entries still parse")
    func garbageReported() throws {
        let e = try Export()
        try e.write(
            "2026-10-27_Oct_26th.html", Export.page(header: "Monday, October 26, 2026", title: "T", body: "<p>ok</p>"))
        try Data((0..<300).map { UInt8($0 % 251) }).write(to: e.root.appending(path: "Entries/2026-10-28_bad.html"))
        let plan = try e.parse()
        #expect(plan.entries.count == 1)
        #expect(plan.failures == [.init(path: "Entries/2026-10-28_bad.html", reason: .notAnEntry)])
    }

    @Test("oversize files and too many files are refused")
    func caps() throws {
        let e = try Export()
        try e.write("2026-10-27_a.html", Export.page(header: "Monday, October 26, 2026", title: "T", body: "<p>ok</p>"))
        var small = AppleJournalParser.Limits()
        small.maxHTMLBytes = 50
        let plan = try e.parse(limits: small)
        #expect(plan.entries.isEmpty && plan.failures.map(\.reason) == [.tooLarge])
        var few = AppleJournalParser.Limits()
        few.maxFiles = 0
        #expect(throws: AppleJournalParseError.tooManyFiles) { try e.parse(limits: few) }
    }

    @Test("a folder without Entries is refused")
    func noEntries() throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "aj-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: AppleJournalParseError.noEntriesFolder) {
            try AppleJournalParser.parse(folder: empty, existingHashes: [], daysWithText: [])
        }
    }

    @Test("known hashes become duplicates; an existing day with text is a conflict")
    func duplicatesAndConflicts() throws {
        let e = try Export()
        try e.write(
            "2026-10-27_a.html", Export.page(header: "Monday, October 26, 2026", title: "T", body: "<p>one</p>"))
        try e.write(
            "2026-10-28_b.html", Export.page(header: "Tuesday, October 27, 2026", title: "T", body: "<p>two</p>"))
        let first = try e.parse(texted: [oct27])
        #expect(first.conflicts == [oct27] && first.entries.count == 2)
        let again = try e.parse(hashes: Set(first.entries.map(\.identityHash)))
        #expect(again.entries.isEmpty && again.duplicates.count == 2 && again.days.isEmpty)
        #expect(again.archiveHash == first.archiveHash)
    }
}

@Suite("Apple Journal import commit")
struct AppleJournalCommitTests {
    private struct Harness {
        let container: ModelContainer
        let store: JournalStore
        let reader: ModelContext

        init() throws {
            container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self), migrationPlan: BeReytMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            store = JournalStore(
                modelContainer: container, clock: { Date(timeIntervalSince1970: 1_790_000_000) },
                timeZone: TimeZone(identifier: "America/Edmonton")!)
            reader = ModelContext(container)
        }

        func records() throws -> [ImportRecord] {
            reader.rollback()
            return try reader.fetch(FetchDescriptor<ImportRecord>(sortBy: [SortDescriptor(\.sectionIndex)]))
        }

        func text(_ key: DateKey) throws -> String? {
            reader.rollback()
            let s = key.string
            return try reader.fetch(FetchDescriptor<DailyEntry>(predicate: #Predicate { $0.dateKey == s })).first?.text
        }

        func plan(_ e: Export) async throws -> AppleJournalImportPlan {
            try e.parse(hashes: try await store.importedSourceHashes(), texted: try await store.daysWithText())
        }
    }

    private let importedAt = Date(timeIntervalSince1970: 1_790_100_000)

    private func twoEntryExport() throws -> Export {
        let e = try Export()
        try e.write(
            "2026-10-27_1.html",
            Export.page(header: "Monday, October 26, 2026", title: "Oct 26th", body: "<p>early</p>"))
        try e.write(
            "2026-10-27_2.html", Export.page(header: "Monday, October 26, 2026", title: "Late", body: "<p>late</p>"))
        try e.write(
            "2026-10-28_1.html",
            Export.page(header: "Tuesday, October 27, 2026", title: "Oct 27th", body: "<p>next</p>"))
        return e
    }

    @Test("commit writes merged days and one record per source entry with section index and title")
    func commitWrites() async throws {
        let h = try Harness()
        let plan = try await h.plan(try twoEntryExport())
        let effect = try await h.store.commitAppleJournalImport(plan: plan, resolutions: [:], importedAt: importedAt)
        #expect(try h.text(oct26) == "early\n\nLate\n\nlate")
        #expect(try h.text(oct27) == "next")
        #expect(effect.contentChangedDays == [oct26, oct27] && effect.dirty)
        let records = try h.records()
        #expect(records.count == 3)
        let day26 = records.filter { $0.targetDateKey == "2026-10-26" }
        #expect(day26.map(\.sectionIndex) == [0, 1])
        #expect(Set(day26.map(\.sourceTitle)) == ["Oct 26th", "Late"])
        #expect(records.allSatisfy { $0.sourceTimestamp == nil && $0.sourceArchiveHash == plan.archiveHash })
    }

    @Test("reimporting the same export finds only duplicates and writes nothing")
    func reimportIsIdempotent() async throws {
        let h = try Harness()
        let e = try twoEntryExport()
        _ = try await h.store.commitAppleJournalImport(
            plan: try await h.plan(e), resolutions: [:], importedAt: importedAt)
        let again = try await h.plan(e)
        #expect(again.entries.isEmpty && again.duplicates.count == 3)
        let effect = try await h.store.commitAppleJournalImport(plan: again, resolutions: [:], importedAt: importedAt)
        #expect(effect.isEmpty)
        #expect(try h.records().count == 3)
        #expect(try h.text(oct26) == "early\n\nLate\n\nlate")
        // Even a stale plan committed twice cannot duplicate records or text.
        let stale = try await h.plan(try twoEntryExport())
        _ = try await h.store.commitAppleJournalImport(plan: stale, resolutions: [:], importedAt: importedAt)
        #expect(try h.records().count == 3)
    }

    @Test("conflict: append keeps existing text and prompt; skip leaves the day alone")
    func conflicts() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(oct26, .text("mine already"))
        _ = try await h.store.assignPromptIfNeeded(oct26) { _, _ in PromptChoice(id: "p1", text: "what helped?") }
        let plan = try await h.plan(try twoEntryExport())
        #expect(plan.conflicts == [oct26])

        _ = try await h.store.commitAppleJournalImport(plan: plan, resolutions: [oct26: .skip], importedAt: importedAt)
        #expect(try h.text(oct26) == "mine already")
        #expect(try h.text(oct27) == "next")
        #expect(try h.records().count == 1)  // the skipped day wrote no records

        let retry = try await h.plan(try twoEntryExport())
        _ = try await h.store.commitAppleJournalImport(
            plan: retry, resolutions: [oct26: .append], importedAt: importedAt)
        #expect(try h.text(oct26) == "mine already\n\nearly\n\nLate\n\nlate")
        h.reader.rollback()
        let prompts = try h.reader.fetch(FetchDescriptor<PromptAssignment>())
        #expect(prompts.map(\.promptID) == ["p1"])
    }

    @Test("a day that only had a score gets the imported text and keeps the score")
    func scoreOnlyDay() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(oct26, .score(.good))
        _ = try await h.store.commitAppleJournalImport(
            plan: try await h.plan(try twoEntryExport()), resolutions: [:], importedAt: importedAt)
        h.reader.rollback()
        let s = oct26.string
        let entry = try #require(
            try h.reader.fetch(FetchDescriptor<DailyEntry>(predicate: #Predicate { $0.dateKey == s })).first)
        #expect(entry.text == "early\n\nLate\n\nlate" && entry.dayScore == DayScore.good.rawValue)
    }

    @Test("import bumps the review week of affected days and purges its narrative")
    func bumpsWeeks() async throws {
        let h = try Harness()
        let weekStart = WeekCalendar.reviewWeekStart(containing: oct26)
        let w = ModelContext(h.container)
        w.insert(
            WeeklyReview(
                weekStartKey: weekStart.string, weekEndKey: weekStart.adding(days: 6).string, timeZoneID: "UTC",
                unlockedAt: Date(timeIntervalSince1970: 0), narrativeJSON: "{\"n\":1}", inputFingerprint: "fp",
                generatedAt: Date(timeIntervalSince1970: 1), promptVersion: 1))
        try w.save()
        let effect = try await h.store.commitAppleJournalImport(
            plan: try await h.plan(try twoEntryExport()), resolutions: [:], importedAt: importedAt)
        #expect(effect.revisionBumpedWeeks == [weekStart])
        h.reader.rollback()
        let s = weekStart.string
        let review = try #require(
            try h.reader.fetch(FetchDescriptor<WeeklyReview>(predicate: #Predicate { $0.weekStartKey == s })).first)
        #expect(review.narrativeJSON == nil && review.sourceRevision == 1)
    }

    @Test("a garbage file leaves the store untouched and is reported; nothing is written for it")
    func parseFailureLeavesStore() async throws {
        let h = try Harness()
        _ = try await h.store.updateEntry(oct26, .text("keep me"))
        let export = try Export()
        try Data((0..<300).map { UInt8($0 % 251) }).write(
            to: export.root.appending(path: "Entries/2026-10-27_bad.html"))
        let plan = try await h.plan(export)
        #expect(plan.entries.isEmpty && plan.failures.count == 1)
        let effect = try await h.store.commitAppleJournalImport(plan: plan, resolutions: [:], importedAt: importedAt)
        #expect(effect.isEmpty)
        #expect(try h.text(oct26) == "keep me" && (try h.records().isEmpty))
    }

    @Test("a read-only store refuses the import and writes nothing")
    func readOnlyRefuses() async throws {
        let h = try Harness()
        let plan = try await h.plan(try twoEntryExport())
        await h.store.setReadOnly(true)
        await #expect(throws: JournalStoreError.readOnly) {
            try await h.store.commitAppleJournalImport(plan: plan, resolutions: [:], importedAt: importedAt)
        }
        #expect(try h.records().isEmpty && (try h.text(oct26)) == nil)
    }
}
