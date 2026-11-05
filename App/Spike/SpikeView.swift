#if DEBUG
    import SwiftUI
    import UniformTypeIdentifiers

    struct SpikeView: View {
        @State private var results = SpikeResults()
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            NavigationStack {
                List {
                    Section("model") {
                        row("1 model", "1-model") { results.run("1-model") { await SpikeChecks.model() } }
                    }
                    Section("health") {
                        row("2 health", "2-health") { results.run("2-health") { await SpikeChecks.health() } }
                    }
                    Section("folder") {
                        row("3a pick folder", "3a-pick-folder") { results.showFolderPicker = true }
                        row("3b resolve bookmark", "3b-resolve-bookmark") {
                            results.run("3b-resolve-bookmark") { SpikeFolder.resolve() }
                        }
                        row("3d upload status", "3d-upload-status") {
                            results.run("3d-upload-status") { SpikeFolder.uploadStatus() }
                        }
                    }
                    Section("archive") {
                        row("4 archive 50 mb", "4-archive-50mb") { archive(50) }
                        row("4 archive 1500 mb", "4-archive-1500mb") { archive(1500) }
                        if results.backgroundedDuringArchive {
                            Text("backgrounded during archive: true").font(.caption)
                        }
                    }
                    Section("device") {
                        row("5 write marker", "5-marker-write") {
                            results.record("5-marker-write", SpikeChecks.writeMarker())
                        }
                        row("5 check marker", "5-marker") { results.record("5-marker", SpikeChecks.markerState()) }
                        row("7 provisioning", "7-provisioning") {
                            results.record("7-provisioning", SpikeChecks.provisioning())
                        }
                    }
                    Section("store protection") {
                        row("9 store protection", "9-store-protection") {
                            results.record("9-store-protection", SpikeStoreCheck.run())
                        }
                        row("9 recheck", "9-store-recheck") {
                            results.record("9-store-recheck", SpikeStoreCheck.recheck())
                        }
                    }
                    Section("results") {
                        Button("copy results") { results.showJSON = true }
                            .frame(minHeight: 44)
                        Text(SpikeResults.fileURL.lastPathComponent).font(.caption)
                    }
                }
                .navigationTitle("spike")
                .disabled(results.running != nil && results.running != "")
            }
            .fileImporter(isPresented: $results.showFolderPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    results.run("3a-pick-folder") { SpikeFolder.pick(url) }
                case .failure(let error):
                    results.record(
                        "3a-pick-folder", SpikeOutcome(ok: false, details: ["error": String(describing: error)]))
                }
            }
            .sheet(isPresented: $results.showJSON) {
                NavigationStack {
                    ScrollView { Text(results.json).font(.caption.monospaced()).textSelection(.enabled).padding() }
                        .toolbar { ShareLink(item: results.json) }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, results.archiveRunning { results.backgroundedDuringArchive = true }
            }
            .task { results.record("5-marker", SpikeChecks.markerState()) }
        }

        private func archive(_ mb: Int) {
            let name = "4-archive-\(mb)mb"
            results.backgroundedDuringArchive = false
            results.archiveRunning = true
            results.record(
                "4-start",
                SpikeOutcome(ok: true, details: ["run": name, "note": "no matching result means interrupted"]))
            results.run(name) { SpikeArchive.run(megabytes: mb) }
            Task {
                while results.running != nil { try? await Task.sleep(for: .milliseconds(200)) }
                var out = results.last(name)?.details ?? [:]
                out["backgroundedDuringArchive"] = "\(results.backgroundedDuringArchive)"
                results.archiveRunning = false
                results.record(
                    "4-archive-flags",
                    SpikeOutcome(ok: true, details: out.filter { $0.key == "backgroundedDuringArchive" }))
            }
        }

        private func row(_ label: String, _ key: String, action: @escaping () -> Void) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Button(label, action: action).frame(minHeight: 44)
                if results.running == key { ProgressView() }
                if let e = results.last(key) {
                    Text(
                        "\(e.ok ? "ok" : "fail") \(e.details.sorted { $0.key < $1.key }.prefix(4).map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
                    )
                    .font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
            }
        }
    }
#endif
