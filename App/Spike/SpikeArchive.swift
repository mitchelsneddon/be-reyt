#if DEBUG
    import AppleArchive
    import CryptoKit
    import Darwin
    import Foundation
    import os
    import System

    enum SpikeArchive {
        struct Failure: Error { let message: String }

        static var protection: [FileAttributeKey: Any] { [.protectionKey: FileProtectionType.completeUnlessOpen] }

        static func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return kr == KERN_SUCCESS ? info.phys_footprint : 0
        }

        /// Runs `body` while a background task samples phys_footprint; returns (result, peak bytes).
        static func measuring<T>(_ body: () throws -> T) throws -> (T, UInt64) {
            let peak = OSAllocatedUnfairLock<UInt64>(initialState: footprint())
            let sampler = Task.detached {
                while !Task.isCancelled {
                    let f = footprint()
                    peak.withLock { $0 = max($0, f) }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { sampler.cancel() }
            let value = try body()
            let f = footprint()
            peak.withLock { $0 = max($0, f) }
            return (value, peak.withLock { $0 })
        }

        static func mb(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }

        /// Writes random files of `fileMB` each, in 1 MB chunks, returning name -> sha256 hex.
        static func generate(in dir: URL, totalMB: Int, fileMB: Int) throws -> [String: String] {
            var hashes: [String: String] = [:]
            var remaining = totalMB
            var index = 0
            while remaining > 0 {
                let size = min(fileMB, remaining)
                let url = dir.appending(path: String(format: "file-%04d.bin", index))
                guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: protection) else {
                    throw Failure(message: "createFile failed")
                }
                let handle = try FileHandle(forWritingTo: url)
                var hasher = SHA256()
                for _ in 0..<size {
                    let chunk = SpikeFolder.randomData(1_048_576)
                    hasher.update(data: chunk)
                    try handle.write(contentsOf: chunk)
                }
                try handle.close()
                hashes[url.lastPathComponent] = hex(hasher.finalize())
                remaining -= size
                index += 1
            }
            return hashes
        }

        static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

        static func sha256(of url: URL) throws -> String {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
            return hex(hasher.finalize())
        }

        static func encrypt(
            directory: URL, to out: URL, profile: ArchiveEncryptionContext.Profile,
            configure: (ArchiveEncryptionContext) throws -> Void
        ) throws {
            let ctx = ArchiveEncryptionContext(profile: profile, compressionAlgorithm: .lzfse)
            try configure(ctx)
            guard
                let file = ArchiveByteStream.fileStream(
                    path: FilePath(out.path), mode: .writeOnly, options: [.create, .truncate],
                    permissions: FilePermissions(rawValue: 0o644)),
                let enc = ArchiveByteStream.encryptionStream(writingTo: file, encryptionContext: ctx),
                let encoder = ArchiveStream.encodeStream(writingTo: enc)
            else { throw Failure(message: "could not open encrypt streams") }
            try encoder.writeDirectoryContents(
                archiveFrom: FilePath(directory.path), keySet: ArchiveHeader.FieldKeySet("TYP,PAT,DAT,SIZ")!)
            try encoder.close()
            try enc.close()
            try file.close()
        }

        static func decrypt(
            archive: URL, to dest: URL, configure: (ArchiveEncryptionContext) throws -> Void
        ) throws {
            guard
                let file = ArchiveByteStream.fileStream(
                    path: FilePath(archive.path), mode: .readOnly, options: [],
                    permissions: FilePermissions(rawValue: 0o644))
            else { throw Failure(message: "could not open archive") }
            guard let ctx = ArchiveEncryptionContext(from: file) else {
                throw Failure(message: "could not read encryption header")
            }
            try configure(ctx)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true, attributes: protection)
            guard
                let dec = ArchiveByteStream.decryptionStream(readingFrom: file, encryptionContext: ctx),
                let decoder = ArchiveStream.decodeStream(readingFrom: dec),
                let extractor = ArchiveStream.extractStream(
                    extractingTo: FilePath(dest.path), flags: [.ignoreOperationNotPermitted])
            else { throw Failure(message: "could not open decrypt streams") }
            _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
            try extractor.close()
            try decoder.close()
            try dec.close()
            try file.close()
        }

        static func verify(hashes: [String: String], in dir: URL) throws -> (matched: Int, mismatched: Int) {
            var good = 0
            var bad = 0
            for (name, expected) in hashes {
                let actual = try? sha256(of: dir.appending(path: name))
                if actual == expected { good += 1 } else { bad += 1 }
            }
            return (good, bad)
        }

        static func run(megabytes: Int) -> SpikeOutcome {
            var d: [String: String] = ["requestedMB": "\(megabytes)"]
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appending(path: "spike-archive-\(UUID().uuidString)")
            defer {
                try? fm.removeItem(at: root)
                d["cleanedUp"] = "true"
            }
            let clock = ContinuousClock()
            do {
                let src = root.appending(path: "src")
                try fm.createDirectory(at: src, withIntermediateDirectories: true, attributes: protection)
                var t = clock.now
                let hashes = try generate(in: src, totalMB: megabytes, fileMB: 5)
                d["generateSeconds"] = spikeSeconds(clock.now - t)
                d["fileCount"] = "\(hashes.count)"

                // (a) portable scrypt password profile
                let out = root.appending(path: "portable.aea")
                t = clock.now
                let (_, encPeak) = try measuring {
                    try encrypt(directory: src, to: out, profile: .hkdf_sha256_aesctr_hmac__scrypt__none) {
                        try $0.setPassword("spike-passphrase-synthetic")
                    }
                }
                d["a.encryptSeconds"] = spikeSeconds(clock.now - t)
                d["a.encryptPeakMB"] = mb(encPeak)
                let size = (try? fm.attributesOfItem(atPath: out.path)[.size] as? UInt64) ?? 0
                d["a.outputMB"] = mb(size)

                // (b) decrypt + verify
                let extracted = root.appending(path: "extracted")
                t = clock.now
                let (_, decPeak) = try measuring {
                    try decrypt(archive: out, to: extracted) { try $0.setPassword("spike-passphrase-synthetic") }
                }
                d["b.decryptSeconds"] = spikeSeconds(clock.now - t)
                d["b.decryptPeakMB"] = mb(decPeak)
                let result = try verify(hashes: hashes, in: extracted)
                d["b.sha256Matched"] = "\(result.matched)"
                d["b.sha256Mismatched"] = "\(result.mismatched)"
                var ok = result.mismatched == 0 && result.matched == hashes.count

                // (c) symmetric profile, single 5 MB blob
                let blobDir = root.appending(path: "blob")
                try fm.createDirectory(at: blobDir, withIntermediateDirectories: true, attributes: protection)
                let blobHashes = try generate(in: blobDir, totalMB: 5, fileMB: 5)
                let key = SymmetricKey(size: .bits256)
                let blobOut = root.appending(path: "blob.aea")
                t = clock.now
                try encrypt(directory: blobDir, to: blobOut, profile: .hkdf_sha256_aesctr_hmac__symmetric__none) {
                    try $0.setSymmetricKey(key)
                }
                let blobExtracted = root.appending(path: "blob-extracted")
                try decrypt(archive: blobOut, to: blobExtracted) { try $0.setSymmetricKey(key) }
                let blobResult = try verify(hashes: blobHashes, in: blobExtracted)
                d["c.roundTripSeconds"] = spikeSeconds(clock.now - t)
                d["c.sha256Matched"] = "\(blobResult.matched)"
                d["c.sha256Mismatched"] = "\(blobResult.mismatched)"
                ok = ok && blobResult.mismatched == 0 && blobResult.matched == 1
                d["completed"] = "true"
                return SpikeOutcome(ok: ok, details: d)
            } catch {
                d["completed"] = "false"
                d["error"] = String(describing: error)
                return SpikeOutcome(ok: false, details: d)
            }
        }
    }
#endif
