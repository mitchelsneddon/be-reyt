import Foundation
import OSLog
import Observation
import ReytKit

/// One snapshot as the restore browser shows it.
struct SnapshotListing: Identifiable, Equatable, Sendable {
    let name: String
    let area: BackupArea
    let day: DateKey
    let bytes: Int?
    /// False when iCloud holds it only as a placeholder: restoring downloads it first.
    let isDownloaded: Bool

    var id: String { "\(area.folder)/\(name)" }
    var isPreRestore: Bool { area == .preRestore }
    var ref: SnapshotRef { SnapshotRef(name: name, area: area) }
}

/// Decides when the automatic backup runs and keeps the status the settings screen shows. Foreground only: a run
/// starts while the app is active, the journal has unbacked changes and has been quiet for about a minute (or on
/// opening, when today's snapshot is missing), and is abandoned, leaving the folder as it was, if the app leaves
/// the foreground. It never runs while the store is read-only (a restore is swapping the data).
@MainActor @Observable
final class BackupManager {
    /// The quiet time after the last edit before a run starts.
    static let idleSeconds: TimeInterval = 60
    /// On opening, a short settle before catching up.
    static let openingDelaySeconds: TimeInterval = 3

    private(set) var index: BackupIndex
    private(set) var isRunning = false
    private(set) var hasDestination = false
    private(set) var folderName: String?
    /// nil until known. False: the folder is only on this iphone.
    private(set) var isUbiquitous: Bool?
    /// iCloud's view of the latest snapshot (and the photos written with it). nil when there is no snapshot.
    private(set) var latestUpload: UploadStatus?
    private(set) var isActive = false
    /// True while restore or delete-all swaps the data: no run starts and no check is scheduled. Set by `suspend()`;
    /// cleared by `resumeAfterQuiesce()`, `didRestore` and `forgetEverything`.
    private(set) var isSuspended = false
    /// How the last run ended, for diagnostics (an error code or outcome, never journal content).
    private(set) var lastOutcome: String?

    @ObservationIgnored private let host: ContainerHost
    @ObservationIgnored private let passphrases: PassphraseStore
    @ObservationIgnored private let dataKeys: DataKeyStore
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<BackupRunner.Output, Never>?
    @ObservationIgnored private var lastEditAt: Date?
    @ObservationIgnored private var changeCounter = 0
    @ObservationIgnored private let logger = Logger(subsystem: "local.mitchel.bereyt", category: "backup")

    #if DEBUG
        /// `-backupFolder <path>`: a plain local folder instead of the picker, never in iCloud.
        @ObservationIgnored private let debugFolder: URL? = {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "-backupFolder"), args.indices.contains(i + 1) else { return nil }
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }()
    #endif

    init(
        host: ContainerHost, passphrases: PassphraseStore = PassphraseStore(), dataKeys: DataKeyStore = DataKeyStore()
    ) {
        self.host = host
        self.passphrases = passphrases
        self.dataKeys = dataKeys
        let loaded = BackupIndex.load(from: host.paths)
        index = loaded
        if !FileManager.default.fileExists(atPath: BackupIndex.url(in: host.paths).path) { persist() }
        hasDestination = bookmarkURL.flatMap { try? Data(contentsOf: $0) } != nil
        #if DEBUG
            if debugFolder != nil { hasDestination = true }
        #endif
    }

    // MARK: Storage

    private var bookmarkURL: URL? {
        host.paths.deviceRoot.appending(path: "backup-bookmark.dat", directoryHint: .notDirectory)
    }

    private func persist() {
        do { try index.save(to: host.paths) } catch {
            logger.error("index save failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Resolves the destination, re-creating a stale bookmark. Throws `folderMissing` when it is gone.
    private func makeDestination() throws -> BookmarkedFolderDestination {
        #if DEBUG
            if let debugFolder { return try BookmarkedFolderDestination(plainFolder: debugFolder) }
        #endif
        guard let file = bookmarkURL, let bookmark = try? Data(contentsOf: file) else {
            throw BackupDestinationError.notConfigured
        }
        let destination = try BookmarkedFolderDestination(bookmark: bookmark)
        if let fresh = destination.refreshedBookmark {
            try? fresh.write(to: file, options: [.atomic, .completeFileProtection])
        }
        return destination
    }

    // MARK: Folder

    /// The folder the user picked: made ready, remembered, and a first backup queued.
    func chooseFolder(_ picked: URL) async {
        do {
            let chosen = try await Task.detached(priority: .userInitiated) {
                try BookmarkedFolderDestination.chosen(picked)
            }.value
            try FileManager.default.createDirectory(at: host.paths.deviceRoot, withIntermediateDirectories: true)
            if let file = bookmarkURL {
                try chosen.bookmark.write(to: file, options: [.atomic, .completeFileProtection])
            }
            hasDestination = true
            folderName = chosen.destination.folderName
            isUbiquitous = chosen.destination.isUbiquitous
            index.lastError = nil
            index.pendingChanges = true
            changeCounter += 1
            persist()
            scheduleCheck(after: Self.openingDelaySeconds)
        } catch {
            index.lastError = .folderMissing
            persist()
        }
    }

    /// Looks at the folder without writing: name, whether it is in iCloud, and that it still exists.
    func refreshDestination() async {
        guard hasDestination else { return }
        do {
            let destination = try makeDestination()
            folderName = destination.folderName
            isUbiquitous = destination.isUbiquitous
            if index.lastError == .folderMissing {
                index.lastError = nil
                persist()
            }
        } catch {
            index.lastError = .folderMissing
            persist()
        }
        await refreshUploadStatus()
    }

    // MARK: Triggers

    /// Called for every persisted journal change.
    func markDirty() {
        changeCounter += 1
        lastEditAt = .now
        if !index.pendingChanges {
            index.pendingChanges = true
            persist()
        }
        scheduleCheck(after: Self.idleSeconds)
    }

    /// The backup passphrase changed: new data key, so every photo is stored again under it on the next run.
    func passphraseChanged() {
        try? dataKeys.rotate()
        markDirty()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            scheduleCheck(after: Self.openingDelaySeconds)
            Task { await refreshDestination() }
        } else {
            timer?.cancel()
            timer = nil
            runTask?.cancel()  // the run abandons its temp files and leaves the folder as it was
        }
    }

    /// Suspends backups and waits for any run to finish, so a swap of the data never has a backup reading it.
    func suspend() async {
        isSuspended = true
        await stopRuns()
    }

    private func stopRuns() async {
        timer?.cancel()
        timer = nil
        runTask?.cancel()
        _ = await runTask?.value
    }

    /// The swap ended (or never happened): backups carry on where they were.
    func resumeAfterQuiesce() {
        isSuspended = false
        scheduleCheck(after: Self.openingDelaySeconds)
    }

    // MARK: Restore

    /// The folder as a destination, for the restore browser and a restore's photo fetches.
    func openDestination() throws -> BookmarkedFolderDestination { try makeDestination() }

    /// Every snapshot in the folder, newest first: the index reconciled with the folder listing, so snapshots only
    /// the folder knows (written by another phone) are included and evicted ones are listed without downloading.
    func listSnapshots() async throws -> [SnapshotListing] {
        let destination = try makeDestination()
        let created = Dictionary(
            index.snapshots.map { ($0.name, $0.createdAt) }, uniquingKeysWith: { first, _ in first })
        return try await Task.detached(priority: .userInitiated) {
            let rows: [(SnapshotListing, Date)] = try destination.list().compactMap { item in
                guard item.area != .blobs, let info = BackupFolderNames.snapshotInfo(fileName: item.name) else {
                    return nil
                }
                let relative = "\(item.area.folder)/\(item.name)"
                let listing = SnapshotListing(
                    name: item.name, area: item.area, day: info.day, bytes: item.bytes,
                    isDownloaded: destination.isDownloaded(relative))
                return (listing, created[item.name] ?? .distantPast)
            }
            return rows.sorted { ($0.0.day, $0.1, $0.0.name) > ($1.0.day, $1.1, $1.0.name) }.map(\.0)
        }.value
    }

    /// The safety copy before a restore: a full verified run into `pre-restore/` (snapshot, plus any photo the
    /// folder lacks). The store is read-only by now; nothing in the folder is replaced or deleted. Throws when it
    /// did not verify, so the restore stops.
    func writePreRestoreCopy(passphrase: String) async throws {
        guard hasDestination else { throw BackupDestinationError.notConfigured }
        guard let store = host.store, let generation = host.generationURL else { throw BackupRunError.coded(.other) }
        let destination = try makeDestination()
        let dataKey = try dataKeys.ensure()
        isRunning = true
        let input = BackupRunner.Input(
            store: store, paths: host.paths, generation: generation, destination: destination, passphrase: passphrase,
            dataKey: dataKey, index: index, today: AppClock.today(), now: .now, appVersion: Self.appVersion,
            kind: .preRestore)
        let task = Task.detached(priority: .userInitiated) { await BackupRunner().run(input) }
        runTask = task
        let output = await task.value
        runTask = nil
        isRunning = false
        // Keep the safety copy and the blobs the run proved; the daily bookkeeping stays as it was.
        var updated = output.index
        updated.pendingChanges = index.pendingChanges
        updated.lastError = index.lastError
        index = updated
        persist()
        if let error = output.error { throw error }
    }

    /// After a restore (or an undo) replaced the journal: a new lineage, so the next daily snapshot never replaces
    /// an older same-day one of the old lineage; the index learns what the restored snapshot references (so
    /// cleanup knows it); this phone keeps its data key, or adopts the snapshot's when it has none; and a fresh
    /// snapshot is queued.
    func didRestore(snapshot: SnapshotRef?, manifest: ArchiveManifest?, dataKey: Data?) {
        index.lineageID = UUID()
        if let snapshot, let manifest, let info = BackupFolderNames.snapshotInfo(fileName: snapshot.name) {
            index.snapshots.removeAll { $0.name == snapshot.name }
            index.snapshots.append(
                KnownSnapshot(
                    name: snapshot.name, dayKey: info.day, lineageID: manifest.lineageID, kind: info.kind,
                    verified: true, createdAt: manifest.createdAt,
                    referencedBlobNames: Set(manifest.attachments.compactMap(\.blob))))
        }
        if let dataKey { try? dataKeys.adoptIfMissing(dataKey) }
        index.pendingChanges = true
        index.lastError = nil
        changeCounter += 1
        persist()
        isSuspended = false
        scheduleCheck(after: Self.openingDelaySeconds)
    }

    /// Delete-all: forget the backup folder, the data key and the index on this phone, in memory as well as on
    /// disk, so a later run cannot write the old index back. Files already in the backup folder are not touched.
    func forgetEverything() async throws {
        await stopRuns()
        dataKeys.clear()
        let fm = FileManager.default
        for url in [BackupIndex.url(in: host.paths), bookmarkURL].compactMap({ $0 })
        where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        index = BackupIndex.load(from: host.paths)
        persist()
        hasDestination = false
        folderName = nil
        isUbiquitous = nil
        latestUpload = nil
        lastOutcome = nil
        isSuspended = false
    }

    private func scheduleCheck(after delay: TimeInterval) {
        guard isActive, !isSuspended else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 0.1)))
            guard !Task.isCancelled else { return }
            await self?.runIfDue()
        }
    }

    private func runIfDue() async {
        guard isActive, !isSuspended, !isRunning, hasDestination else { return }
        let now = Date.now
        if let lastEditAt, now.timeIntervalSince(lastEditAt) < Self.idleSeconds {
            return scheduleCheck(after: Self.idleSeconds - now.timeIntervalSince(lastEditAt))
        }
        let today = AppClock.today()
        let due = BackupPlan.isDue(
            dirty: index.pendingChanges, today: today, lineageID: index.lineageID, snapshots: index.snapshots,
            now: now)
        if due { return await run() }
        if index.pendingChanges, let latest = index.snapshots.map(\.createdAt).max() {
            let remaining = BackupPlan.refreshInterval - now.timeIntervalSince(latest)
            if remaining > 0 { scheduleCheck(after: remaining + 1) }
        }
    }

    /// "back up now": runs when the app is active, without waiting for a quiet minute.
    func backUpNow() async {
        guard isActive, !isSuspended else { return }
        timer?.cancel()
        await run()
    }

    // MARK: Run

    private func run() async {
        guard isActive, !isSuspended, !isRunning, hasDestination else { return }
        guard let passphrase = passphrases.stored() else { return }
        guard let store = host.store, let generation = host.generationURL else {
            return scheduleCheck(after: Self.openingDelaySeconds)  // the journal isn't open yet (phone locked)
        }
        let destination: BookmarkedFolderDestination
        let dataKey: Data
        do {
            destination = try makeDestination()
            dataKey = try dataKeys.ensure()
        } catch {
            index.lastError = (error as? BackupDestinationError) == .folderMissing ? .folderMissing : .other
            persist()
            return
        }
        isUbiquitous = destination.isUbiquitous
        folderName = destination.folderName
        isRunning = true
        let startedAtChange = changeCounter
        let input = BackupRunner.Input(
            store: store, paths: host.paths, generation: generation, destination: destination, passphrase: passphrase,
            dataKey: dataKey, index: index, today: AppClock.today(), now: .now, appVersion: Self.appVersion)
        let task = Task.detached(priority: .utility) { await BackupRunner().run(input) }
        runTask = task
        let output = await task.value
        runTask = nil
        isRunning = false

        let stillPending = changeCounter != startedAtChange
        lastOutcome = output.error.map { String(describing: $0) } ?? "ok"
        var updated = output.index
        updated.pendingChanges = true
        switch output.error {
        case nil:
            updated.pendingChanges = stillPending
        case .cancelled?:
            break  // left the foreground or the store went read-only: nothing is wrong, try again later
        case .sourceChanged?:
            if isActive { scheduleCheck(after: 30) }
        case .coded(let code)?:
            updated.lastError = code
        }
        index = updated
        persist()
        if output.error == nil {
            latestUpload = .uploading
            await refreshUploadStatus()
            if stillPending { scheduleCheck(after: Self.idleSeconds) }
        }
    }

    // MARK: Upload status

    /// Reads iCloud's upload state for the latest snapshot and the photos written with it. "uploaded" only when
    /// every one of them says so.
    func refreshUploadStatus() async {
        guard hasDestination, let name = index.lastSnapshotName, let destination = try? makeDestination() else {
            latestUpload = nil
            return
        }
        let blobs = index.latestRunBlobs
        let status = await Task.detached(priority: .utility) { () -> UploadStatus in
            let snapshot = destination.uploadStatus("\(BackupFolderNames.snapshots)/\(name)")
            if snapshot == .notUbiquitous || snapshot == .missing || snapshot == .error { return snapshot }
            let others = blobs.compactMap { BlobNaming.relativePath(for: $0) }.map { destination.uploadStatus($0) }
            if others.contains(.error) { return .error }
            return snapshot == .uploaded && others.allSatisfy({ $0 == .uploaded || $0 == .missing })
                ? .uploaded : .uploading
        }.value
        latestUpload = status == .missing ? nil : status
        if status == .uploaded, let written = index.lastSnapshotWrittenAt, index.lastUploadConfirmedAt != written {
            index.lastUploadConfirmedAt = written
            persist()
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return
            "\(info?["CFBundleShortVersionString"] as? String ?? "0") (\(info?["CFBundleVersion"] as? String ?? "0"))"
    }
}
