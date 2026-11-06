import SwiftUI

/// Markdown and PDF copies of the journal, for reading rather than restoring. Not encrypted, and says so.
struct ReadableExportView: View {
    @State private var model: ReadableExportModel

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
                .frame(minHeight: 44)
                if model.customRange {
                    DatePicker(
                        Copy.ReadableExport.startLabel, selection: $model.start, in: ...model.today,
                        displayedComponents: .date
                    )
                    .frame(minHeight: 44)
                    DatePicker(
                        Copy.ReadableExport.endLabel, selection: $model.end, in: ...model.today,
                        displayedComponents: .date
                    )
                    .frame(minHeight: 44)
                }
                Toggle(
                    Copy.ReadableExport.workoutsToggle,
                    isOn: Binding(get: { model.includeWorkouts }, set: { model.setIncludeWorkouts($0) })
                )
                .frame(minHeight: 44)
            } header: {
                Text(Copy.ReadableExport.rangeSection)
            } footer: {
                Text(Copy.ReadableExport.workoutsFooter)
            }
            Section {
                exportRow(Copy.ReadableExport.markdownRow, .markdown)
                exportRow(Copy.ReadableExport.pdfRow, .pdf)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.ReadableExport.notEncrypted).foregroundStyle(Palette.ink)
                    Text(Copy.ReadableExport.footer)
                    if let message = statusNote { Text(message).foregroundStyle(Palette.ink) }
                }
            }
        }
        .navigationTitle(Copy.ReadableExport.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
        .tint(Palette.accent)
        .task { await model.load() }
        .fileExporter(
            isPresented: $model.showExporter, item: model.file,
            contentTypes: model.file.map { [$0.contentType] } ?? [.zip],
            defaultFilename: model.suggestedName,
            onCompletion: { model.exporterFinished($0) }, onCancellation: { model.exporterCancelled() }
        )
    }

    private func exportRow(_ title: String, _ kind: ReadableExportModel.Kind) -> some View {
        Button {
            Task { await model.export(kind) }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if model.isWorking { ProgressView() }
            }
        }
        .disabled(model.isWorking)
        .frame(minHeight: 44)
    }

    private var statusNote: String? {
        switch model.state {
        case .working(let fraction):
            if let fraction { return Copy.ReadableExport.progress(Int(fraction * 100)) }
            return Copy.ReadableExport.working
        case .failed(let message): return message
        case .idle: return model.note
        }
    }
}
