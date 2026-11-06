import SwiftUI

/// Markdown and PDF copies of the journal, for reading rather than restoring. Not encrypted, and says so.
struct ReadableExportView: View {
    @State private var model: ReadableExportModel
    @State private var activeKind: ReadableExportModel.Kind?

    init(host: ContainerHost) {
        _model = State(initialValue: ReadableExportModel(host: host))
    }

    var body: some View {
        List {
            Section {
                Picker(Copy.ReadableExport.rangeLabel, selection: $model.customRange) {
                    Text(Copy.ReadableExport.rangeAll).tag(false)
                    Text(Copy.ReadableExport.rangeCustom).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 52)
                if model.customRange {
                    datePicker(Copy.ReadableExport.startLabel, selection: $model.start)
                    datePicker(Copy.ReadableExport.endLabel, selection: $model.end)
                }
                Toggle(isOn: Binding(get: { model.includeWorkouts }, set: { model.setIncludeWorkouts($0) })) {
                    Text(Copy.ReadableExport.workoutsToggle).brFont(.row).foregroundStyle(Palette.ink)
                }
                .frame(minHeight: 52)
            } header: {
                SettingsHeader(Copy.ReadableExport.rangeSection)
            }
            .settingsRows()
            Section {
                exportRow(Copy.ReadableExport.markdownRow, icon: "doc.text", .markdown)
                exportRow(Copy.ReadableExport.pdfRow, icon: "doc.richtext", .pdf)
            } footer: {
                VStack(alignment: .leading, spacing: 14) {
                    status
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.open").foregroundStyle(Palette.ink).accessibilityHidden(true)
                        Text(Copy.ReadableExport.notEncrypted).foregroundStyle(Palette.ink)
                    }
                    .brFont(.banner)
                    .accessibilityElement(children: .combine)
                }
                .textCase(nil)
                .padding(.top, 6)
            }
            .settingsRows()
        }
        .listSectionSpacing(28)
        .navigationTitle(Copy.ReadableExport.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .tint(Palette.accent)
        .task {
            await model.load()
            #if DEBUG
                // Simulator-only: `-exportDebugWorking` shows the pdf row mid-export at 62%.
                if CommandLine.arguments.contains("-exportDebugWorking") {
                    activeKind = .pdf
                    model.debugShowWorking(0.62)
                }
            #endif
        }
        .fileExporter(
            isPresented: $model.showExporter, item: model.file,
            contentTypes: model.file.map { [$0.contentType] } ?? [.zip],
            defaultFilename: model.suggestedName,
            onCompletion: { model.exporterFinished($0) }, onCancellation: { model.exporterCancelled() }
        )
    }

    private func datePicker(_ title: String, selection: Binding<Date>) -> some View {
        DatePicker(selection: selection, in: ...model.today, displayedComponents: .date) {
            Text(title).brFont(.row).foregroundStyle(Palette.ink)
        }
        .datePickerStyle(.compact)
        .tint(Palette.accent)
        .frame(minHeight: 52)
        .accessibilityLabel(title)
    }

    private func exportRow(_ title: String, icon: String, _ kind: ReadableExportModel.Kind) -> some View {
        Button {
            activeKind = kind
            Task { await model.export(kind) }
        } label: {
            SettingsAction(title: title, icon: icon, busy: model.isWorking && activeKind == kind)
        }
        .disabled(model.isWorking)
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .working(let fraction):
            VStack(alignment: .leading, spacing: 10) {
                Text(fraction.map { Copy.ReadableExport.progress(Int($0 * 100)) } ?? Copy.ReadableExport.working)
                    .brFont(.rowWrapping).foregroundStyle(Palette.ink2)
                if let fraction { progressBar(fraction) }
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle").accessibilityLabel(Copy.Settings.problem)
                Text(message)
            }
            .brFont(.rowWrapping).foregroundStyle(Palette.danger)
            .accessibilityElement(children: .combine)
        case .idle:
            if let note = model.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
                        .accessibilityHidden(true)
                    Text(note).foregroundStyle(Palette.ink)
                }
                .brFont(.rowWrapping)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.chip)
                Capsule().fill(Palette.accent).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
