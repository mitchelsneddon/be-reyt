import Foundation
import SwiftData
import Testing

@testable import ReytKit

@Suite("Archive payload")
struct ArchiveTests {
    @Test("fully populated journal round-trips: write, validate, build generation, fetch, compare DTOs")
    func roundTrip() async throws {
        let f = try await ArchiveFixture()
        let raw = try f.rawData()
        // Guard the fixture itself: every record type is present.
        #expect(!raw.entries.isEmpty && !raw.tags.isEmpty && !raw.attachments.isEmpty)
        #expect(!raw.promptAssignments.isEmpty && !raw.intentions.isEmpty && raw.reviews.count == 2)
        #expect(!raw.workouts.isEmpty && !raw.importRecords.isEmpty)
        #expect(raw.settings == AppSettingsDTO(reminderEnabled: false, reminderHour: 7, includeWorkoutsInExports: true))

        let payload = try await f.writePayload()
        let validated = try ArchiveValidator.validate(directory: payload)
        #expect(validated.data == raw)
        #expect(validated.warnings.isEmpty)
        #expect(validated.counts.entries == 2 && validated.counts.attachments == 2 && validated.counts.tags == 2)
        #expect(validated.dateRange == ArchiveManifest.DateRange(first: "2026-11-02", last: "2026-11-04"))
        #expect(validated.manifest.kind == .portable && validated.manifest.timeZone == "Europe/London")

        let switcher = GenerationSwitcher(paths: f.paths)
        let built = try switcher.build(from: validated)
        #expect(built.id == "g2")
        let restored = try GenerationSwitcher.openContainer(at: f.paths.store(in: built.directory))
        #expect(try ArchiveData.fetch(from: ModelContext(restored)) == raw)

        let copiedA = try f.paths.resolveAttachment(relativePath: raw.attachments[0].relativePath, in: built.directory)
        let all = try raw.attachments.map {
            try Data(contentsOf: f.paths.resolveAttachment(relativePath: $0.relativePath, in: built.directory))
        }
        #expect(all.contains(f.photoABytes) && all.contains(f.photoBBytes))
        #expect(FileManager.default.fileExists(atPath: copiedA.path))
    }

    @Test("dates are written as ISO8601 with fractional seconds and keys are sorted")
    func jsonShape() async throws {
        let f = try await ArchiveFixture()
        let payload = try await f.writePayload()
        let text = try String(contentsOf: payload.appending(path: "data.json"), encoding: .utf8)
        #expect(text.contains("\"createdAt\":\"2026-09-21T14:13:20.250Z\""))
        let manifest = try String(contentsOf: payload.appending(path: "manifest.json"), encoding: .utf8)
        #expect(manifest.hasPrefix("{\"appVersion\""))  // sortedKeys
        #expect(manifest.contains("\"format\":\"be-reyt-archive\""))
    }

    @Test("unknown JSON fields are ignored on read")
    func unknownFields() async throws {
        let f = try await ArchiveFixture()
        let payload = try await f.writePayload()
        let dataURL = payload.appending(path: "data.json")
        var data = try readJSON(dataURL)
        data["futureField"] = ["x": 1]
        var entries = try #require(data["entries"] as? [[String: Any]])
        entries[0]["someNewThing"] = "hello"
        data["entries"] = entries
        try writeJSON(data, to: dataURL)
        var manifest = try readJSON(payload.appending(path: "manifest.json"))
        manifest["extra"] = true
        try writeJSON(manifest, to: payload.appending(path: "manifest.json"))
        let validated = try ArchiveValidator.validate(directory: payload)
        #expect(validated.data == (try f.rawData()))
    }

    @Test("every persisted property of every SchemaV1 record has a DTO field, and no more")
    func dtoCompleteness() {
        // Reliable source: the SwiftData schema's own property list. `Mirror` on an @Model instance shows the macro's
        // `_$backingData`/`_$observationRegistrar` storage rather than the declared properties, so it is not used.
        func names<K: CaseIterable & RawRepresentable>(_: K.Type) -> Set<String> where K.RawValue == String {
            Set(K.allCases.map(\.rawValue))
        }
        let dtoKeys: [String: Set<String>] = [
            "DailyEntry": names(DailyEntryDTO.CodingKeys.self),
            "AppSettings": names(AppSettingsDTO.CodingKeys.self),
            "PromptAssignment": names(PromptAssignmentDTO.CodingKeys.self),
            "Tag": names(TagDTO.CodingKeys.self),
            "Attachment": names(AttachmentDTO.CodingKeys.self),
            "WorkoutSnapshot": names(WorkoutSnapshotDTO.CodingKeys.self),
            "WeeklyReview": names(WeeklyReviewDTO.CodingKeys.self),
            "WeeklyIntention": names(WeeklyIntentionDTO.CodingKeys.self),
            "ImportRecord": names(ImportRecordDTO.CodingKeys.self),
        ]
        let entities = Schema(versionedSchema: SchemaV1.self).entities
        #expect(Set(entities.map(\.name)) == Set(dtoKeys.keys))
        for entity in entities {
            let stored = Set(entity.storedProperties.map(\.name))
            #expect(!stored.isEmpty)
            #expect(stored == dtoKeys[entity.name], "\(entity.name) and its DTO disagree")
        }
        // The data.json root covers one collection per record type.
        #expect(names(ArchiveData.CodingKeys.self).count == dtoKeys.count)
    }

    @Test("a stale narrative is omitted from the payload, a valid one is kept, and the store is not purged")
    func staleNarrative() async throws {
        let f = try await ArchiveFixture()
        try await f.addReview(week: ArchiveFixture.staleWeek, valid: false)
        let c = ModelContext(f.container)
        let stale = try #require(
            try c.fetch(FetchDescriptor<WeeklyReview>()).first { $0.weekStartKey == ArchiveFixture.staleWeek.string })
        let staleWeek = stale.weekStartKey

        let payload = try await f.writePayload()
        let data = try ArchiveValidator.validate(directory: payload).data
        let kept = try #require(data.reviews.first { $0.weekStartKey == ArchiveFixture.validWeek.string })
        #expect(kept.narrativeJSON != nil && kept.inputFingerprint != nil && kept.generatedAt != nil)
        let dropped = try #require(data.reviews.first { $0.weekStartKey == staleWeek })
        #expect(dropped.narrativeJSON == nil && dropped.inputFingerprint == nil && dropped.generatedAt == nil)
        // Other fields survive.
        #expect(dropped.moreOfThisText == "keep" && dropped.promptVersion == 1 && dropped.osBuild == "27A2")
        #expect(dropped.sourceRevision == 1 && dropped.moreOfThisTargetEndKey == "2026-11-15")
        // The live store keeps its narrative (the check never purges).
        let live = try ModelContext(f.container).fetch(FetchDescriptor<WeeklyReview>()).first {
            $0.weekStartKey == staleWeek
        }
        #expect(live?.narrativeJSON != nil)
    }
}

@Suite("Archive snapshot consistency")
struct SnapshotConsistencyTests {
    actor Counter {
        var n = 0
        func next() -> Int {
            n += 1
            return n
        }
    }

    @Test("a write between the read and the attachment copy triggers a retry; the payload has the new state")
    func retry() async throws {
        let f = try await ArchiveFixture()
        let calls = Counter()
        let store = f.store
        var writer = ArchiveWriter(paths: f.paths, generation: f.generation)
        writer.afterSnapshotRead = {
            if await calls.next() == 1 {
                _ = try? await store.updateEntry(ArchiveFixture.entryDay, .text("changed mid-copy"))
            }
        }
        let dir = f.base.appending(path: "retry-payload")
        try await writer.write(
            from: store, to: dir,
            options: .init(kind: .portable, appVersion: "1", lineageID: UUID()))
        #expect(await calls.n == 2)
        let data = try ArchiveValidator.validate(directory: dir).data
        let entry = try #require(data.entries.first { $0.dateKey == ArchiveFixture.entryDay.string })
        #expect(entry.text == "changed mid-copy")
        #expect(data == (try f.rawData()))
    }

    @Test("a store that keeps changing gives up after 3 attempts and leaves no payload")
    func givesUp() async throws {
        let f = try await ArchiveFixture()
        let calls = Counter()
        let store = f.store
        var writer = ArchiveWriter(paths: f.paths, generation: f.generation)
        writer.afterSnapshotRead = {
            let n = await calls.next()
            _ = try? await store.updateEntry(ArchiveFixture.entryDay, .text("w\(n)"))
        }
        let dir = f.base.appending(path: "never")
        await #expect(throws: ArchiveError.storeChanged) {
            try await writer.write(
                from: store, to: dir, options: .init(kind: .portable, appVersion: "1", lineageID: UUID()))
        }
        #expect(await calls.n == 3)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("a no-op update does not move the counter; a real write does")
    func counter() async throws {
        let f = try await ArchiveFixture()
        let before = await f.store.generationCounter()
        _ = try await f.store.updateEntry(ArchiveFixture.entryDay, .text(try f.rawData().entries[1].text))
        let same = await f.store.generationCounter()
        _ = try await f.store.updateEntry(ArchiveFixture.entryDay, .text("new text"))
        #expect(same == before)
        #expect(await f.store.generationCounter() > before)
    }

    @Test("a destination that already has files is refused and left alone")
    func destinationNotEmpty() async throws {
        let f = try await ArchiveFixture()
        let dir = f.base.appending(path: "occupied")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: dir.appending(path: "x"))
        await #expect(throws: ArchiveError.destinationNotEmpty) {
            try await ArchiveWriter(paths: f.paths, generation: f.generation).write(
                from: f.store, to: dir, options: .init(kind: .portable, appVersion: "1", lineageID: UUID()))
        }
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "x").path))
    }
}

@Suite("Archive validator")
struct ArchiveValidatorTests {
    struct Payload {
        let f: ArchiveFixture
        let dir: URL
    }

    private func payload() async throws -> Payload {
        let f = try await ArchiveFixture()
        return Payload(f: f, dir: try await f.writePayload())
    }

    private func attachmentURL(_ dir: URL, _ f: ArchiveFixture) -> URL {
        dir.appending(path: "attachments/\(f.photoB.uuidString.lowercased()).png")
    }

    @Test("a valid payload passes with no warnings")
    func valid() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        #expect(try ArchiveValidator.validate(directory: dir).warnings.isEmpty)
    }

    @Test(
        "manifest attachment extension that traverses is rejected",
        arguments: ["../../evil", "a/b", "", "PNG", "png/.."])
    func extensionTraversal(ext: String) async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        var m = try readJSON(dir.appending(path: "manifest.json"))
        var items = try #require(m["attachments"] as? [[String: Any]])
        items[0]["ext"] = ext
        m["attachments"] = items
        try writeJSON(m, to: dir.appending(path: "manifest.json"))
        #expect(throws: ArchiveError.unsafePath("attachment extension")) {
            try ArchiveValidator.validate(directory: dir)
        }
    }

    @Test(
        "data.json attachment path that traverses or is absolute is rejected",
        arguments: ["../x.png", "/etc/passwd", "a/../../b.png", "a\\b.png"])
    func relativePathTraversal(path: String) async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        var d = try readJSON(dir.appending(path: "data.json"))
        var items = try #require(d["attachments"] as? [[String: Any]])
        items[0]["relativePath"] = path
        d["attachments"] = items
        try writeJSON(d, to: dir.appending(path: "data.json"))
        #expect(throws: ArchiveError.unsafePath(path)) { try ArchiveValidator.validate(directory: dir) }
    }

    @Test("a symlink inside the payload is rejected, even one that points outside")
    func symlink() async throws {
        let p = try await payload()
        let f = p.f
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        let outside = f.base.appending(path: "outside.txt")
        try Data("secret".utf8).write(to: outside)
        let link = attachmentURL(dir, f)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(throws: ArchiveError.unsafePath("attachments/\(f.photoB.uuidString.lowercased()).png")) {
            try ArchiveValidator.validate(directory: dir)
        }
    }

    @Test("a file over the per-file cap is rejected")
    func oversizedFile() async throws {
        let p = try await payload()
        let f = p.f
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        let limits = ArchiveValidator.Limits(perFileBytes: 1_000_000, totalBytes: .max)
        #expect(throws: ArchiveError.fileTooLarge("attachments/\(f.photoA.uuidString.lowercased()).heic")) {
            try ArchiveValidator.validate(directory: dir, limits: limits)
        }
    }

    @Test("a payload over the total cap is rejected")
    func oversizedTotal() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        let limits = ArchiveValidator.Limits(perFileBytes: .max, totalBytes: 1_000)
        #expect(throws: ArchiveError.totalTooLarge) { try ArchiveValidator.validate(directory: dir, limits: limits) }
    }

    @Test("a corrupted attachment (same size, different bytes) fails its checksum")
    func checksumMismatch() async throws {
        let p = try await payload()
        let f = p.f
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        try Data("TINY".utf8).write(to: attachmentURL(dir, f))
        #expect(throws: ArchiveError.checksumMismatch("attachments/\(f.photoB.uuidString.lowercased()).png")) {
            try ArchiveValidator.validate(directory: dir)
        }
    }

    @Test("a truncated attachment fails its size check")
    func sizeMismatch() async throws {
        let p = try await payload()
        let f = p.f
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        try Data("ti".utf8).write(to: attachmentURL(dir, f))
        #expect(throws: ArchiveError.sizeMismatch("attachments/\(f.photoB.uuidString.lowercased()).png")) {
            try ArchiveValidator.validate(directory: dir)
        }
    }

    @Test("a missing attachment is rejected for portable, and tolerated for snapshot until staged")
    func missingAttachment() async throws {
        let p = try await payload()
        let f = p.f
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        try FileManager.default.removeItem(at: attachmentURL(dir, f))
        #expect(throws: ArchiveError.missingFile("attachments/\(f.photoB.uuidString.lowercased()).png")) {
            try ArchiveValidator.validate(directory: dir)
        }
        let snap = try await f.writePayload(kind: .snapshot)
        let validated = try ArchiveValidator.validate(directory: snap)
        #expect(validated.manifest.kind == .snapshot && validated.manifest.attachments.count == 2)
        let first = try #require(validated.manifest.attachments.first)
        #expect(throws: ArchiveError.missingFile("attachments/\(first.id.uuidString.lowercased()).\(first.ext)")) {
            try ArchiveValidator.validate(directory: snap, verifyAttachmentFiles: true)
        }
    }

    @Test("a portable export skips an attachment whose file is missing on disk and warns")
    func exportSkipsMissingAttachment() async throws {
        let f = try await ArchiveFixture()
        try FileManager.default.removeItem(at: f.attachmentFile("\(f.photoB.uuidString.lowercased()).png"))
        let dir = f.base.appending(path: "payload-missing")
        let options = ArchiveWriter.Options(
            kind: .portable, appVersion: "1.0 (1)", lineageID: UUID(), createdAt: f.t(20),
            timeZone: TimeZone(identifier: "Europe/London")!)
        let manifest = try await ArchiveWriter(paths: f.paths, generation: f.generation)
            .write(from: f.store, to: dir, options: options)
        #expect(manifest.warnings == [ArchiveWarning.missingAttachment])
        #expect(manifest.counts.attachments == 1 && manifest.attachments.map(\.id) == [f.photoA])

        let validated = try ArchiveValidator.validate(directory: dir)
        #expect(validated.data.attachments.map(\.id) == [f.photoA])
        #expect(validated.warnings.contains(ArchiveWarning.missingAttachment))
        // everything else is untouched
        #expect(validated.data.entries == (try f.rawData()).entries)
        // the source journal still lists the record: the export never edits the live store
        #expect(try f.rawData().attachments.count == 2)
    }

    @Test("a snapshot leaves out an excluded attachment (record and blob) and warns")
    func snapshotExcludesAttachment() async throws {
        let f = try await ArchiveFixture()
        let dir = f.base.appending(path: "payload-excluded")
        var options = ArchiveWriter.Options(
            kind: .snapshot, appVersion: "1.0 (1)", lineageID: UUID(), createdAt: f.t(20),
            timeZone: TimeZone(identifier: "Europe/London")!, dataKey: Data(repeating: 7, count: 32))
        options.excludedAttachmentIDs = [f.photoB]
        let manifest = try await ArchiveWriter(paths: f.paths, generation: f.generation)
            .write(from: f.store, to: dir, options: options)
        #expect(manifest.warnings == [ArchiveWarning.missingAttachment])
        #expect(manifest.attachments.map(\.id) == [f.photoA])
        #expect(manifest.attachments.allSatisfy { $0.blob != nil })
        let validated = try ArchiveValidator.validate(directory: dir)
        #expect(validated.data.attachments.map(\.id) == [f.photoA])
    }

    @Test("an export with every file present has no warnings field")
    func noWarningsWhenComplete() async throws {
        let f = try await ArchiveFixture()
        let dir = try await f.writePayload()
        #expect(try ArchiveReader.readManifest(in: dir, maxBytes: 1 << 20).warnings == nil)
    }

    @Test("manifest counts that disagree with data.json are rejected")
    func countMismatch() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        var m = try readJSON(dir.appending(path: "manifest.json"))
        var counts = try #require(m["counts"] as? [String: Int])
        counts["entries"] = 99
        m["counts"] = counts
        try writeJSON(m, to: dir.appending(path: "manifest.json"))
        #expect(throws: ArchiveError.countMismatch("manifest counts differ from data.json")) {
            try ArchiveValidator.validate(directory: dir)
        }
    }

    @Test("an archive from a newer schema version is refused as newer, even if its shape changed")
    func newerVersion() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        try writeJSON(
            ["format": "be-reyt-archive", "schemaVersion": 2, "somethingNew": [1]],
            to: dir.appending(path: "manifest.json"))
        #expect(throws: ArchiveError.newerVersion(found: 2)) { try ArchiveValidator.validate(directory: dir) }
    }

    @Test("a wrong format is not an archive; missing files and bad JSON are reported")
    func notAnArchive() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        var m = try readJSON(dir.appending(path: "manifest.json"))
        m["format"] = "something-else"
        try writeJSON(m, to: dir.appending(path: "manifest.json"))
        #expect(throws: ArchiveError.notAnArchive) { try ArchiveValidator.validate(directory: dir) }
        let p2 = try await payload()
        let dir2 = p2.dir
        defer { withExtendedLifetime(p2) {} }
        try Data("{not json".utf8).write(to: dir2.appending(path: "data.json"))
        #expect(throws: ArchiveError.malformed("data")) { try ArchiveValidator.validate(directory: dir2) }
        try FileManager.default.removeItem(at: dir2.appending(path: "data.json"))
        #expect(throws: ArchiveError.missingFile("data.json")) { try ArchiveValidator.validate(directory: dir2) }
    }

    @Test("an invalid date key and a duplicate unique key are rejected")
    func recordChecks() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        var d = try readJSON(dir.appending(path: "data.json"))
        var entries = try #require(d["entries"] as? [[String: Any]])
        entries[0]["dateKey"] = "2026-13-40"
        d["entries"] = entries
        try writeJSON(d, to: dir.appending(path: "data.json"))
        #expect(throws: ArchiveError.invalidDateKey("entries.dateKey")) {
            try ArchiveValidator.validate(directory: dir)
        }

        let p2 = try await payload()
        let dir2 = p2.dir
        defer { withExtendedLifetime(p2) {} }
        var d2 = try readJSON(dir2.appending(path: "data.json"))
        var e2 = try #require(d2["entries"] as? [[String: Any]])
        e2[1]["dateKey"] = e2[0]["dateKey"]
        d2["entries"] = e2
        try writeJSON(d2, to: dir2.appending(path: "data.json"))
        #expect(throws: ArchiveError.duplicateKey("entries.dateKey")) { try ArchiveValidator.validate(directory: dir2) }
    }

    @Test("an attachment on a day with no entry is accepted (photo-only day)")
    func photoOnlyDay() async throws {
        let p = try await payload()
        let dir = p.dir
        defer { withExtendedLifetime(p) {} }
        let v = try ArchiveValidator.validate(directory: dir)
        #expect(v.data.attachments.contains { $0.entryDateKey == ArchiveFixture.photoOnlyDay })
        #expect(!v.data.entries.contains { $0.dateKey == ArchiveFixture.photoOnlyDay })
    }
}
