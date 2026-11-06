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
                .background(Palette.paper)
                .navigationTitle(Copy.Import.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    FlowTitle(text: Copy.Import.title)
                    ToolbarItem(placement: .cancellationAction) { leading }
                }
        }
        .tint(Palette.accent)
    }

    /// Cancel while reading, previewing or after a failure; "done" when the preview found nothing new.
    @ViewBuilder private var leading: some View {
        switch importer.phase {
        case .importing, .finished: EmptyView()
        case .preview where importer.plan?.isEmpty == true:
            Button(Copy.Import.done) { importer.dismiss() }.brFont(.navAction)
        default:
            Button(Copy.Import.cancel) { importer.dismiss() }.brFont(.navAction)
        }
    }

    @ViewBuilder private var content: some View {
        switch importer.phase {
        case .idle: Palette.paper
        case .reading(let done, let total): reading(done: done, total: total)
        case .importing: FlowBusy(Copy.Import.importingTitle, serif: true)
        case .preview:
            if let plan = importer.plan { PreviewList(importer: importer, plan: plan) }
        case .finished: finished
        case .failed(let message):
            FlowNotice(
                icon: "exclamationmark.triangle", text: message, disc: Palette.chip, tint: Palette.ink2, side: 64,
                prominent: true
            ) {
                EmptyView()
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar { Button(Copy.Import.close) { importer.dismiss() }.buttonStyle(.brOutline) }
            }
        }
    }

    private func reading(done: Int, total: Int) -> some View {
        FlowBusy(Copy.Import.readingTitle, serif: true) {
            if total > 0 {
                VStack(spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.chip)
                            Capsule().fill(Palette.accent)
                                .frame(width: proxy.size.width * min(max(Double(done) / Double(total), 0), 1))
                        }
                    }
                    .frame(width: 240, height: 4)
                    .accessibilityHidden(true)
                    Text(Copy.Import.progress(done: done, total: total)).brFont(.banner)
                        .foregroundStyle(Palette.ink2)
                }
            }
        }
    }

    @ViewBuilder private var finished: some View {
        if let result = importer.result {
            VStack(spacing: 20) {
                Image(systemName: "checkmark")
                    .resizable().scaledToFit().frame(width: 26, height: 26)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ok)
                    .frame(width: 64, height: 64)
                    .background(Palette.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(Copy.Import.resultTitle).brFont(.onboardingTitle).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                VStack(spacing: 6) {
                    Text(Copy.Import.resultLine(entries: result.entries, days: result.days))
                        .brFont(.navAction).foregroundStyle(Palette.ink)
                    if let photos = Copy.Import.photosResult(
                        imported: result.photosImported, failed: result.photosFailed)
                    {
                        Text(photos).brFont(.rowWrapping).foregroundStyle(Palette.ink2)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                bottomBar { Button(Copy.Import.done) { importer.dismiss() }.buttonStyle(.brPrimary) }
            }
        }
    }

    private func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Palette.paper)
            .overlay(alignment: .top) { Palette.border.frame(height: 1) }
    }
}

private struct PreviewList: View {
    let importer: AppleJournalImporter
    let plan: AppleJournalImportPlan

    var body: some View {
        if plan.isEmpty {
            FlowNotice(
                icon: "checkmark",
                text: plan.duplicates.isEmpty ? Copy.Import.nothingNew : Copy.Import.nothingNewDetail,
                side: 64, prominent: true)
        } else {
            list
                .safeAreaInset(edge: .bottom) {
                    Button(Copy.Import.importAction) { importer.confirm() }
                        .buttonStyle(.brPrimary)
                        .accessibilityHint(Copy.Import.noTimes)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                        .background(Palette.paper)
                        .overlay(alignment: .top) { Palette.border.frame(height: 1) }
                }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !plan.isEmpty { section(Copy.Import.willImportSection) { summaryCard } }
                if !plan.duplicates.isEmpty {
                    section(Copy.Import.alreadyImportedSection) {
                        Text(Copy.Import.alreadyImported(plan.duplicates.count)).brFont(.row)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !plan.conflicts.isEmpty {
                    section(Copy.Import.conflictsSection) {
                        rows(plan.conflicts.map { $0 }) { day in conflictRow(day) }
                    }
                }
                if !plan.unsupported.isEmpty {
                    section(Copy.Import.unsupportedSection) {
                        rows(Array(plan.unsupported.enumerated()).map { $0 }) { pair in
                            twoLine(pair.element.description, fileLabel(pair.element.entryPath))
                        }
                    }
                }
                if !plan.failures.isEmpty {
                    section(Copy.Import.failuresSection) {
                        rows(plan.failures.map { $0 }) { failure in
                            twoLine(fileLabel(failure.path), Copy.Import.failure(failure.reason))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsHeader(title).padding(.horizontal, 16).accessibilityAddTraits(.isHeader)
            content()
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.Import.summary(entries: plan.entries.count, days: plan.days.count))
                .brFont(.stat).foregroundStyle(Palette.ink)
            if plan.photoCount > 0 {
                Text(Copy.Import.photos(plan.photoCount)).brFont(.row).foregroundStyle(Palette.ink)
            }
            if let range = plan.dateRange {
                Text(Copy.Import.range(first: dayLabel(range.lowerBound), last: dayLabel(range.upperBound)))
                    .brFont(.rowWrapping).foregroundStyle(Palette.ink2)
            }
            if plan.fallbackDateCount > 0 {
                Text(Copy.Import.fallbackNote).brFont(.banner).foregroundStyle(Palette.ink2)
            }
            Text(Copy.Import.noTimes).brFont(.banner).foregroundStyle(Palette.ink2)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Palette.border.frame(height: 1) }
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rows separated by hairlines inside a card.
    private func rows<Item, Row: View>(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Palette.border.frame(height: 1) }
                row(item)
            }
        }
    }

    private func twoLine(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).brFont(.row).foregroundStyle(Palette.ink)
            Text(detail).brFont(.label).foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func conflictRow(_ day: DateKey) -> some View {
        let current = importer.resolution(for: day)
        return HStack(spacing: 12) {
            Text(dayLabel(day)).brFont(.row).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                segment(Copy.Import.append, on: current == .append) { importer.resolutions[day] = .append }
                segment(Copy.Import.skip, on: current == .skip) { importer.resolutions[day] = .skip }
            }
            .padding(3)
            .background(Palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Copy.Import.conflictLabel(dayLabel(day)))
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 6)
        .frame(minHeight: 56)
    }

    // shortcut: segments are 34 high as on the board; the hit area is stretched to 44 with a contentShape
    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).brFont(on ? .labelBold : .label)
                .foregroundStyle(on ? Palette.onAccent : Palette.ink)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 34)
                .background(
                    on ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
            Button(action: choose) {
                SettingsAction(title: Copy.Import.row, icon: "book.closed")
            }
            .accessibilityHint(Copy.Import.rowHint)
        } header: {
            SettingsHeader(Copy.Import.settingsSection)
        }
        .settingsRows()
    }
}
