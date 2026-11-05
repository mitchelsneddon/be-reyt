import SwiftUI

/// The evening reminder: a switch, the hour, and calm guidance when notifications are off in iOS.
struct ReminderSection: View {
    @Environment(ReminderScheduler.self) private var reminders

    var body: some View {
        Section {
            Toggle(
                Copy.Reminder.toggle,
                isOn: Binding(
                    get: { reminders.settings.enabled }, set: { value in Task { await reminders.setEnabled(value) } })
            )
            .frame(minHeight: 44)
            if reminders.settings.enabled {
                Picker(
                    Copy.Reminder.time,
                    selection: Binding(
                        get: { reminders.settings.hour }, set: { value in Task { await reminders.setHour(value) } })
                ) {
                    ForEach(0..<24, id: \.self) { Text(Copy.Reminder.hourLabel($0)).tag($0) }
                }
                .frame(minHeight: 44)
                permissionRows
            }
        } header: {
            Text(Copy.Reminder.section)
        } footer: {
            Text(Copy.Reminder.footer)
        }
        .task { await reminders.refresh() }
    }

    @ViewBuilder private var permissionRows: some View {
        switch reminders.permission {
        case .notDetermined:
            Button(Copy.Reminder.allow) { Task { await reminders.requestAuthorizationIfNeeded() } }
                .accessibilityHint(Copy.Reminder.allowHint)
                .frame(minHeight: 44, alignment: .leading)
        case .denied:
            Text(Copy.Reminder.denied).foregroundStyle(Color("inkSecondary"))
            Button(Copy.Reminder.openSettings) { reminders.openSystemSettings() }
                .accessibilityHint(Copy.Reminder.openSettingsHint)
                .frame(minHeight: 44, alignment: .leading)
        case .unknown, .allowed:
            EmptyView()
        }
    }
}
