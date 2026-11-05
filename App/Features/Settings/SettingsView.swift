import SwiftUI

/// The settings tab.
struct SettingsView: View {
    let backup: BackupSettingsModel
    let restore: RestoreCoordinator

    var body: some View {
        NavigationStack {
            ExportImportView(backup: backup, restore: restore)
                .navigationTitle(Copy.Settings.title)
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
