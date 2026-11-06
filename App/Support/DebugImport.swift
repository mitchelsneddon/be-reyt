#if DEBUG
    import Foundation

    /// Simulator-only drivers for the Apple Journal import, so it can run without the folder picker:
    /// `-importJournalFrom <folder>` opens the preview, `-autoConfirmImport` also confirms it (with every conflict
    /// set to append) and closes the result after two seconds (`-importHold` keeps the result open).
    enum DebugImport {
        @MainActor
        static func runIfRequested(host: ContainerHost, importer: AppleJournalImporter) async {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "-importJournalFrom"), args.indices.contains(i + 1) else { return }
            var waited = 0
            while host.store == nil, waited < 400 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            importer.begin(folder: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            guard args.contains("-autoConfirmImport") else { return }
            while importer.phase != .preview, importer.isPresented, waited < 2400 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            guard importer.phase == .preview else { return }
            importer.confirm()
            while importer.phase != .finished, importer.isPresented, waited < 4800 {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 1
            }
            guard !args.contains("-importHold") else { return }
            try? await Task.sleep(for: .seconds(2))
            importer.dismiss()
        }
    }
#endif
