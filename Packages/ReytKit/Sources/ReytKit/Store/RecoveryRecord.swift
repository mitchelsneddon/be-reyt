import Foundation

/// The generation a restore replaced, kept for seven days so "undo last restore" can flip back to it.
/// Lives in `Device/recovery.json`; device-local state, never archived.
public struct RecoveryRecord: Codable, Equatable, Sendable {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    public var generationID: String
    public var recordedAt: Date

    public init(generationID: String, recordedAt: Date) {
        self.generationID = generationID
        self.recordedAt = recordedAt
    }

    public func isAvailable(now: Date) -> Bool {
        now.timeIntervalSince(recordedAt) < Self.retention && now >= recordedAt.addingTimeInterval(-60)
    }

    /// The record on disk, or nil when absent or unreadable (the file is untrusted: the id is re-validated).
    public static func load(from paths: Paths) -> RecoveryRecord? {
        guard let data = try? Data(contentsOf: paths.recoveryFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(RecoveryRecord.self, from: data),
            Paths.isValidGenerationID(record.generationID)
        else { return nil }
        return record
    }

    public func save(to paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.deviceRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: paths.recoveryFile, options: .atomic)
    }

    public static func clear(from paths: Paths) {
        try? FileManager.default.removeItem(at: paths.recoveryFile)
    }
}
