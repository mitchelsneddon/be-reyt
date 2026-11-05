#if DEBUG
    import Foundation
    import Security

    enum SpikeFolder {
        static let bookmarkKey = "spike.folderBookmark"
        static let subfolder = "be reyt spike"

        static func randomData(_ count: Int) -> Data {
            var data = Data(count: count)
            let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
            return status == errSecSuccess ? data : Data(repeating: 0xA5, count: count)
        }

        /// Coordinated write of a file inside the (already security-scoped) spike folder.
        static func coordinatedWrite(_ data: Data, to url: URL) throws {
            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(
                writingItemAt: url, options: .forReplacing, error: &coordError
            ) { target in
                do { try data.write(to: target, options: [.atomic]) } catch { writeError = error }
            }
            if let e = coordError ?? writeError { throw e }
        }

        /// 3a: runs with a freshly picked folder URL.
        static func pick(_ url: URL) -> SpikeOutcome {
            var d: [String: String] = [:]
            let scoped = url.startAccessingSecurityScopedResource()
            d["scoped"] = "\(scoped)"
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            d["pickedFolderName"] = url.lastPathComponent
            d["pathComponents"] = url.pathComponents.suffix(4).joined(separator: "/")
            do {
                let bookmark = try url.bookmarkData()
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
                d["bookmarkBytes"] = "\(bookmark.count)"
                let sub = url.appending(path: subfolder, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                let file = sub.appending(path: "random-1mb-\(Int(Date.now.timeIntervalSince1970)).bin")
                try coordinatedWrite(randomData(1_048_576), to: file)
                d["wrote"] = file.lastPathComponent
                d["isUbiquitousItem"] = String(
                    describing: (try? file.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem)
                return SpikeOutcome(ok: true, details: d)
            } catch {
                d["error"] = String(describing: error)
                return SpikeOutcome(ok: false, details: d)
            }
        }

        /// Resolves the saved bookmark, runs `body` with scoped access to the spike subfolder.
        static func withFolder(_ d: inout [String: String], _ body: (URL, inout [String: String]) throws -> Void)
            -> Bool
        {
            guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
                d["error"] = "no saved bookmark"
                return false
            }
            var stale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                d["isStale"] = "\(stale)"
                let scoped = url.startAccessingSecurityScopedResource()
                d["scoped"] = "\(scoped)"
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let sub = url.appending(path: subfolder, directoryHint: .isDirectory)
                try body(sub, &d)
                return true
            } catch {
                d["error"] = String(describing: error)
                return false
            }
        }

        static func resolve() -> SpikeOutcome {
            var d: [String: String] = [:]
            let ok = withFolder(&d) { sub, d in
                let names = try FileManager.default.contentsOfDirectory(
                    at: sub, includingPropertiesForKeys: nil, options: []
                ).map(\.lastPathComponent).sorted()
                d["listing"] = names.joined(separator: " | ")
                d["listingCount"] = "\(names.count)"
                let file = sub.appending(path: "random-1mb-resolved-\(Int(Date.now.timeIntervalSince1970)).bin")
                try coordinatedWrite(randomData(1_048_576), to: file)
                d["wrote"] = file.lastPathComponent
            }
            return SpikeOutcome(ok: ok, details: d)
        }

        static func uploadStatus() -> SpikeOutcome {
            var d: [String: String] = [:]
            let keys: [(String, URLResourceKey)] = [
                ("isUbiquitousItem", .isUbiquitousItemKey),
                ("isUploaded", .ubiquitousItemIsUploadedKey),
                ("isUploading", .ubiquitousItemIsUploadingKey),
                ("uploadingError", .ubiquitousItemUploadingErrorKey),
                ("downloadingStatus", .ubiquitousItemDownloadingStatusKey),
                ("fileSize", .fileSizeKey),
            ]
            let ok = withFolder(&d) { sub, d in
                let files = try FileManager.default.contentsOfDirectory(
                    at: sub, includingPropertiesForKeys: nil, options: [])
                var nilKeys = Set<String>()
                var valueKeys = Set<String>()
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    var parts: [String] = []
                    for (label, key) in keys {
                        let raw = try? file.resourceValues(forKeys: [key]).allValues[key]
                        if let raw {
                            parts.append("\(label)=\(raw)")
                            valueKeys.insert(label)
                        } else {
                            parts.append("\(label)=nil")
                            nilKeys.insert(label)
                        }
                    }
                    d[file.lastPathComponent] = parts.joined(separator: " ")
                }
                d["keysWithValues"] = valueKeys.sorted().joined(separator: ",")
                d["keysNilOnSomeFile"] = nilKeys.sorted().joined(separator: ",")
            }
            return SpikeOutcome(ok: ok, details: d)
        }
    }
#endif
