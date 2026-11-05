import ReytKit
import SwiftUI

extension View {
    /// Presents the Apple Journal import flow (reading, preview, result) above whatever tab is showing.
    func appleJournalImportSheet(_ importer: AppleJournalImporter) -> some View {
        sheet(
            isPresented: Binding(get: { importer.isPresented }, set: { if !$0 { importer.dismiss() } })
        ) {
            ImportPreviewView(importer: importer).interactiveDismissDisabled(importer.phase == .importing)
        }
    }
}

/// Preview before anything is written: counts, dates, what is skipped, and a choice per conflicting day.
struct ImportPreviewView: View {
    let importer: AppleJournalImporter

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Copy.Import.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if importer.phase != .importing && importer.phase != .finished {
                            Button(Copy.Import.cancel) { importer.dismiss() }
                        }
                    }
                }
        }
        .tint(Color("accent"))
    }

    @ViewBuilder private var content: some View {
        switch importer.phase {
        case .idle: Color("paper")
        case .reading(let done, let total):
            busy(Copy.Import.readingTitle, detail: total > 0 ? Copy.Import.progress(done: done, total: total) : nil)
        case .importing: busy(Copy.Import.importingTitle, detail: nil)
        case .preview:
            if let plan = importer.plan { PreviewList(importer: importer, plan: plan) }
        case .finished: finished
        case .failed(let message):
            notice(message)
        }
    }

    private func busy(_ title: String, detail: String?) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).font(.body).foregroundStyle(Color("ink"))
            if let detail { Text(detail).font(.footnote).foregroundStyle(Color("inkSecondary")) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("paper"))
        .accessibilityElement(children: .combine)
    }

    private func notice(_ text: String) -> some View {
        VStack(spacing: 16) {
            Text(text).font(.body).foregroundStyle(Color("ink")).multilineTextAlignment(.center)
            Button(Copy.Import.close) { importer.dismiss() }.frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("paper"))
    }

    @ViewBuilder private var finished: some View {
        if let result = importer.result {
            VStack(spacing: 12) {
                Text(Copy.Import.resultTitle).font(.headline).foregroundStyle(Color("ink"))
                Text(Copy.Import.resultLine(entries: result.entries, days: result.days))
                    .foregroundStyle(Color("ink"))
                if let photos = Copy.Import.photosResult(imported: result.photosImported, failed: result.photosFailed) {
                    Text(photos).foregroundStyle(Color("inkSecondary"))
                }
                Button(Copy.Import.done) { importer.dismiss() }.frame(minHeight: 44)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("paper"))
        }
    }
}

private struct PreviewList: View {
    let importer: AppleJournalImporter
    let plan: AppleJournalImportPlan

    var body: some View {
        List {
            if plan.isEmpty {
                Section {
                    Text(plan.duplicates.isEmpty ? Copy.Import.nothingNew : Copy.Import.nothingNewDetail)
                        .foregroundStyle(Color("ink"))
                }
            } else {
                Section {
                    Text(
                        Copy.Import.summary(entries: plan.entries.count, days: plan.days.count, photos: plan.photoCount)
                    )
                    .foregroundStyle(Color("ink"))
                    if let range = plan.dateRange {
                        Text("\(dayLabel(range.lowerBound)) – \(dayLabel(range.upperBound))")
                            .foregroundStyle(Color("inkSecondary"))
                    }
                } header: {
                    Text(Copy.Import.willImportSection)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Copy.Import.noTimes)
                        if plan.fallbackDateCount > 0 { Text(Copy.Import.fallbackNote) }
                    }
                }
            }
            if !plan.duplicates.isEmpty {
                Section(Copy.Import.alreadyImportedSection) { Text(Copy.Import.alreadyImported(plan.duplicates.count)) }
            }
            if !plan.conflicts.isEmpty {
                Section {
                    ForEach(plan.conflicts, id: \.self) { day in
                        Picker(
                            dayLabel(day),
                            selection: Binding(
                                get: { importer.resolution(for: day) }, set: { importer.resolutions[day] = $0 })
                        ) {
                            Text(Copy.Import.append).tag(AppleJournalConflictResolution.append)
                            Text(Copy.Import.skip).tag(AppleJournalConflictResolution.skip)
                        }
                        .accessibilityLabel(Copy.Import.conflictLabel(dayLabel(day)))
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text(Copy.Import.conflictsSection)
                } footer: {
                    Text(Copy.Import.conflictsFooter)
                }
            }
            if !plan.unsupported.isEmpty {
                Section {
                    ForEach(Array(plan.unsupported.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.description).foregroundStyle(Color("ink"))
                            Text(fileLabel(item.entryPath)).font(.footnote).foregroundStyle(Color("inkSecondary"))
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(Copy.Import.unsupportedSection)
                } footer: {
                    Text(Copy.Import.unsupportedFooter)
                }
            }
            if !plan.failures.isEmpty {
                Section {
                    ForEach(plan.failures, id: \.path) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileLabel(failure.path)).foregroundStyle(Color("ink"))
                            Text(Copy.Import.failure(failure.reason)).font(.footnote)
                                .foregroundStyle(Color("inkSecondary"))
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(Copy.Import.failuresSection)
                } footer: {
                    Text(Copy.Import.failuresFooter)
                }
            }
            if !plan.isEmpty {
                Section {
                    Button(Copy.Import.importAction) { importer.confirm() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityHint(Copy.Import.noTimes)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("paper"))
    }

    private func dayLabel(_ day: DateKey) -> String {
        day.date(in: .current).formatted(.dateTime.day().month(.abbreviated).year()).lowercased()
    }

    private func fileLabel(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }
}

/// The settings row that starts the flow; the folder picker is attached by the caller.
struct ImportSection: View {
    let choose: () -> Void

    var body: some View {
        Section {
            Button(Copy.Import.row, action: choose)
                .accessibilityHint(Copy.Import.rowHint)
                .frame(minHeight: 44, alignment: .leading)
        } header: {
            Text(Copy.Import.settingsSection)
        } footer: {
            Text(Copy.Import.sectionFooter)
        }
    }
}
