import Foundation
import Testing

@testable import ReytKit

@Suite("Backup plan")
struct BackupPlanTests {
    static let today = DateKey("2026-11-05")!
    static let lineage = UUID()
    static let otherLineage = UUID()
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Snapshot written on `today - daysAgo`, at noon that day (so createdAt order follows the day).
    func daily(
        _ daysAgo: Int, lineage: UUID = BackupPlanTests.lineage, verified: Bool = true, refs: Set<String>? = [],
        name: String? = nil
    ) -> KnownSnapshot {
        KnownSnapshot(
            name: name ?? "daily-\(daysAgo)-\(lineage.uuidString.prefix(4))", dayKey: Self.today.adding(days: -daysAgo),
            lineageID: lineage, kind: .daily, verified: verified,
            createdAt: Self.now.addingTimeInterval(-Double(daysAgo) * 86_400), referencedBlobNames: refs)
    }

    func preRestore(_ daysAgo: Int, refs: Set<String>? = []) -> KnownSnapshot {
        KnownSnapshot(
            name: "pre-\(daysAgo)", dayKey: Self.today.adding(days: -daysAgo), lineageID: Self.lineage,
            kind: .preRestore, verified: true, createdAt: Self.now.addingTimeInterval(-Double(daysAgo) * 86_400),
            referencedBlobNames: refs)
    }

    func cleanup(
        _ snapshots: [KnownSnapshot], new: String, blobs: Set<String> = [], extraListed: Set<String> = [],
        verified: Bool = true
    ) -> BackupPlan.Cleanup {
        BackupPlan.cleanup(
            runVerified: verified, newSnapshot: new, snapshots: snapshots,
            folderSnapshotNames: Set(snapshots.map(\.name)).union(extraListed), folderBlobNames: blobs, now: Self.now)
    }

    // MARK: Due

    @Test("not due when nothing changed, even with no snapshot today")
    func notDueWhenClean() {
        #expect(
            !BackupPlan.isDue(dirty: false, today: Self.today, lineageID: Self.lineage, snapshots: [], now: Self.now))
    }

    @Test("due when dirty and there is no verified snapshot today in this lineage")
    func dueWhenNoneToday() {
        #expect(BackupPlan.isDue(dirty: true, today: Self.today, lineageID: Self.lineage, snapshots: [], now: Self.now))
        // yesterday's snapshot, an unverified one today, and another lineage's one today do not count
        let others = [daily(1), daily(0, verified: false, name: "u"), daily(0, lineage: Self.otherLineage)]
        #expect(
            BackupPlan.isDue(dirty: true, today: Self.today, lineageID: Self.lineage, snapshots: others, now: Self.now))
    }

    @Test("a fresh snapshot today is not refreshed until the interval has passed")
    func refreshInterval() {
        let fresh = KnownSnapshot(
            name: "s", dayKey: Self.today, lineageID: Self.lineage, verified: true,
            createdAt: Self.now.addingTimeInterval(-60), referencedBlobNames: [])
        #expect(
            !BackupPlan.isDue(
                dirty: true, today: Self.today, lineageID: Self.lineage, snapshots: [fresh], now: Self.now))
        let later = Self.now.addingTimeInterval(BackupPlan.refreshInterval)
        #expect(
            BackupPlan.isDue(dirty: true, today: Self.today, lineageID: Self.lineage, snapshots: [fresh], now: later))
    }

    // MARK: Replace

    @Test("a same-day snapshot is replaced only within its own lineage")
    func replaceWithinLineage() {
        let mine = daily(0)
        let theirs = daily(0, lineage: Self.otherLineage)
        let yesterday = daily(1)
        let targets = BackupPlan.replacementTargets(
            today: Self.today, lineageID: Self.lineage, snapshots: [mine, theirs, yesterday])
        #expect(targets == [mine.name])
    }

    @Test("after a new snapshot verifies, only the same-day same-lineage one is deleted; another lineage keeps its day")
    func cleanupReplacesOnlySameLineage() {
        let old = daily(0, name: "old-today")
        let other = daily(0, lineage: Self.otherLineage, name: "other-lineage-today")
        let new = KnownSnapshot(
            name: "new-today", dayKey: Self.today, lineageID: Self.lineage, verified: true, createdAt: Self.now,
            referencedBlobNames: [])
        let result = cleanup([old, other, new], new: "new-today")
        #expect(result.snapshotsToDelete == ["old-today"])
        #expect(Set(result.kept) == ["other-lineage-today", "new-today"])  // two snapshots that day, across lineages
    }

    // MARK: Retention

    @Test("the 31st verified daily snapshot prunes the oldest, and only the oldest")
    func thirtyFirstPrunesOldest() {
        let snapshots = (0..<31).map { daily($0) }  // 0 is today (new), 30 days ago is the oldest
        let result = cleanup(snapshots, new: daily(0).name)
        #expect(result.snapshotsToDelete == [daily(30).name])
        #expect(result.kept.count == 30)
    }

    @Test("30 snapshots prune nothing")
    func thirtyPrunesNothing() {
        let snapshots = (0..<30).map { daily($0) }
        #expect(cleanup(snapshots, new: daily(0).name).snapshotsToDelete.isEmpty)
    }

    @Test("retention counts verified dailies across lineages")
    func retentionAcrossLineages() {
        var snapshots = (0..<20).map { daily($0) }
        snapshots += (21..<32).map { daily($0, lineage: Self.otherLineage) }  // 11 more, 31 in total
        let result = cleanup(snapshots, new: daily(0).name)
        #expect(result.snapshotsToDelete == [daily(31, lineage: Self.otherLineage).name])
    }

    @Test("a pre-restore snapshot younger than 30 days is never pruned, however many dailies there are")
    func preRestoreKept() {
        let snapshots = (0..<35).map { daily($0) } + [preRestore(29)]
        let result = cleanup(snapshots, new: daily(0).name)
        #expect(!result.snapshotsToDelete.contains("pre-29"))
        #expect(result.kept.contains("pre-29"))
        #expect(result.kept.count == 31)  // 30 dailies + the pre-restore copy
    }

    @Test("a pre-restore snapshot older than 30 days is pruned")
    func preRestoreExpired() {
        let result = cleanup([daily(0), preRestore(31)], new: daily(0).name)
        #expect(result.snapshotsToDelete == ["pre-31"])
        #expect(!result.kept.contains("pre-31"))
    }

    @Test("an unverified snapshot is neither kept nor deleted, and does not count towards retention")
    func unverifiedIgnored() {
        let snapshots = (0..<30).map { daily($0) } + [daily(40, verified: false, name: "junk")]
        let result = cleanup(snapshots, new: daily(0).name)
        #expect(result.snapshotsToDelete.isEmpty)
        #expect(!result.kept.contains("junk"))
    }

    // MARK: GC

    @Test("GC deletes only blobs that no kept snapshot references")
    func gcDeletesOnlyUnreferenced() {
        let a = daily(0, refs: ["blobA", "blobB"], name: "s0")
        let b = daily(1, refs: ["blobB", "blobC"], name: "s1")
        let result = cleanup([a, b], new: "s0", blobs: ["blobA", "blobB", "blobC", "blobOld"])
        #expect(result.blobsToDelete == ["blobOld"])
        #expect(!result.cleanupPaused)
    }

    @Test("a blob referenced only by a pruned snapshot is deleted; one still used by a kept snapshot survives")
    func gcFollowsPruning() {
        var snapshots = (1..<30).map { daily($0, refs: ["shared"], name: "d\($0)") }
        snapshots.append(daily(31, refs: ["shared", "onlyOld"], name: "d31"))
        snapshots.insert(daily(0, refs: ["shared", "fresh"], name: "d0"), at: 0)
        let result = cleanup(snapshots, new: "d0", blobs: ["shared", "onlyOld", "fresh"])
        #expect(result.snapshotsToDelete == ["d31"])
        #expect(result.blobsToDelete == ["onlyOld"])
    }

    @Test("a replaced same-day snapshot's blobs are released only if the new snapshot doesn't use them")
    func gcAfterReplace() {
        let old = daily(0, refs: ["keepMe", "dropMe"], name: "old")
        let new = KnownSnapshot(
            name: "new", dayKey: Self.today, lineageID: Self.lineage, verified: true, createdAt: Self.now,
            referencedBlobNames: ["keepMe", "added"])
        let result = cleanup([old, new], new: "new", blobs: ["keepMe", "dropMe", "added"])
        #expect(result.snapshotsToDelete == ["old"])
        #expect(result.blobsToDelete == ["dropMe"])
    }

    @Test("GC is skipped and cleanup is paused when any kept snapshot's references are unknown")
    func gcPausedOnUnknownRefs() {
        let known = daily(0, refs: ["a"], name: "s0")
        let unknown = daily(1, refs: nil, name: "s1")
        let result = cleanup([known, unknown], new: "s0", blobs: ["a", "orphan"])
        #expect(result.blobsToDelete.isEmpty)
        #expect(result.cleanupPaused)
    }

    @Test("a snapshot in the folder that the index has never seen pauses cleanup (new phone, empty index)")
    func gcPausedOnStrangers() {
        let mine = daily(0, refs: ["a"], name: "s0")
        let result = cleanup([mine], new: "s0", blobs: ["a", "theirs"], extraListed: ["be-reyt-from-old-phone.aea"])
        #expect(result.blobsToDelete.isEmpty)
        #expect(result.cleanupPaused)
    }

    @Test("an unknown-reference snapshot that is being pruned does not hold GC back")
    func unknownButPruned() {
        var snapshots = (0..<30).map { daily($0, refs: ["a"], name: "d\($0)") }
        snapshots.append(daily(40, refs: nil, name: "ancient"))
        let result = cleanup(snapshots, new: "d0", blobs: ["a", "orphan"])
        #expect(result.snapshotsToDelete == ["ancient"])
        #expect(result.blobsToDelete == ["orphan"])
        #expect(!result.cleanupPaused)
    }

    // MARK: Failure

    @Test("a run that did not verify deletes nothing, whatever the state")
    func failedRunDeletesNothing() {
        let snapshots = (0..<35).map { daily($0, refs: ["a"]) } + [preRestore(40)]
        let result = cleanup(snapshots, new: daily(0).name, blobs: ["a", "orphan"], verified: false)
        #expect(result == BackupPlan.Cleanup())
    }

    @Test("a new snapshot that isn't verified in the index or isn't in the folder deletes nothing")
    func newSnapshotMustBeVerifiedAndListed() {
        let snapshots = (0..<35).map { daily($0, refs: ["a"]) }
        let unverifiedNew = snapshots.map { s -> KnownSnapshot in
            var s = s
            if s.name == daily(0).name { s.verified = false }
            return s
        }
        #expect(cleanup(unverifiedNew, new: daily(0).name, blobs: ["orphan"]) == BackupPlan.Cleanup())
        let notListed = BackupPlan.cleanup(
            runVerified: true, newSnapshot: daily(0).name, snapshots: snapshots,
            folderSnapshotNames: Set(snapshots.dropFirst().map(\.name)), folderBlobNames: ["orphan"], now: Self.now)
        #expect(notListed == BackupPlan.Cleanup())
    }

    @Test("an index entry whose file has gone from the folder is not a restore point and doesn't count")
    func vanishedSnapshotIgnored() {
        let snapshots = (0..<31).map { daily($0, refs: ["a"]) }
        // the oldest file was deleted by the user in Files: 30 remain, so nothing needs pruning
        let listed = Set(snapshots.dropLast().map(\.name))
        let result = BackupPlan.cleanup(
            runVerified: true, newSnapshot: daily(0).name, snapshots: snapshots, folderSnapshotNames: listed,
            folderBlobNames: [], now: Self.now)
        #expect(result.snapshotsToDelete.isEmpty)
    }
}

@Suite("Blob naming")
struct BlobNamingTests {
    let sha = String(repeating: "ab", count: 32)

    @Test("the same content and key always give the same name; a different key gives a different one")
    func deterministicPerKey() throws {
        let k1 = Data(repeating: 1, count: 32)
        let k2 = Data(repeating: 2, count: 32)
        let a = try #require(BlobNaming.name(dataKey: k1, plaintextSHA256: sha))
        #expect(a == BlobNaming.name(dataKey: k1, plaintextSHA256: sha))
        #expect(a != BlobNaming.name(dataKey: k2, plaintextSHA256: sha))
        #expect(a != BlobNaming.name(dataKey: k1, plaintextSHA256: String(repeating: "cd", count: 32)))
        #expect(BlobNaming.isValidName(a))
        #expect(a != sha)  // the name never equals the plain checksum
    }

    @Test("a known vector: HMAC-SHA256 over the raw digest bytes")
    func vector() throws {
        // key = 32 x 0x00, message = 32 x 0xab; expected value computed independently with Python hmac.
        let name = try #require(BlobNaming.name(dataKey: Data(count: 32), plaintextSHA256: sha))
        #expect(name == "b79816df3b61d162fe0710b14d15ef3d038a29a2b657f9660d2fecf0625b37bf")
    }

    @Test("bad keys and checksums give no name; paths are blobs/xx/name.aea")
    func rejectsBadInput() throws {
        #expect(BlobNaming.name(dataKey: Data(count: 31), plaintextSHA256: sha) == nil)
        #expect(BlobNaming.name(dataKey: Data(count: 32), plaintextSHA256: "zz") == nil)
        let name = try #require(BlobNaming.name(dataKey: Data(count: 32), plaintextSHA256: sha))
        #expect(BlobNaming.relativePath(for: name) == "blobs/\(name.prefix(2))/\(name).aea")
        #expect(BlobNaming.relativePath(for: "../x") == nil)
        #expect(BlobNaming.name(fromFileName: "\(name).aea") == name)
        #expect(BlobNaming.name(fromFileName: "\(name).txt") == nil)
    }
}
