import SwiftUI

/// The evening reminder: a switch, the hour, and calm guidance when notifications are off in iOS.
struct ReminderSection: View {
    @Environment(ReminderScheduler.self) private var reminders

    var body: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { reminders.settings.enabled }, set: { value in Task { await reminders.setEnabled(value) } })
            ) {
                SettingsRowLabel(title: Copy.Reminder.toggle, icon: "bell")
            }
            if reminders.settings.enabled {
                Picker(
                    selection: Binding(
                        get: { reminders.settings.hour }, set: { value in Task { await reminders.setHour(value) } })
                ) {
                    ForEach(0..<24, id: \.self) { Text(Copy.Reminder.hourLabel($0)).tag($0) }
                } label: {
                    SettingsRowLabel(title: Copy.Reminder.time, icon: "clock")
                }
                .brFont(.row)
                .tint(Palette.ink2)
                permissionRows
            }
        } header: {
            SettingsHeader(Copy.Reminder.section)
        }
        .settingsRows()
        .task { await reminders.refresh() }
    }

    @ViewBuilder private var permissionRows: some View {
        switch reminders.permission {
        case .notDetermined:
            Button {
                Task { await reminders.requestAuthorizationIfNeeded() }
            } label: {
                SettingsAction(title: Copy.Reminder.allow)
            }
            .accessibilityHint(Copy.Reminder.allowHint)
        case .denied:
            SettingsNote(text: Copy.Reminder.denied)
            Button {
                reminders.openSystemSettings()
            } label: {
                SettingsAction(title: Copy.Reminder.openSettings)
            }
            .accessibilityHint(Copy.Reminder.openSettingsHint)
        case .unknown, .allowed:
            EmptyView()
        }
    }
}
