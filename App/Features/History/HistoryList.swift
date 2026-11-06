import ReytKit
import SwiftUI

/// Days newest first, grouped under lowercase month headers. Rows push the day page through the stack's path.
struct HistoryList: View {
    let days: [DaySummary]

    private struct Month: Identifiable {
        let id: Int
        let header: String
        let days: [DaySummary]
    }

    /// `days` arrive newest first, so months are contiguous runs.
    private var months: [Month] {
        var result: [Month] = []
        for day in days {
            let id = day.dateKey.year * 12 + day.dateKey.month
            if result.last?.id == id {
                result[result.count - 1] = Month(
                    id: id, header: result[result.count - 1].header, days: result[result.count - 1].days + [day])
            } else {
                result.append(
                    Month(
                        id: id, header: Copy.History.monthHeader(year: day.dateKey.year, month: day.dateKey.month),
                        days: [day]))
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(months) { month in
                Section {
                    ForEach(month.days) { day in
                        NavigationLink(value: day.dateKey) { DaySummaryRow(summary: day) }
                            .navigationLinkIndicatorVisibility(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Palette.card)
                            .listRowSeparatorTint(Palette.border)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } header: {
                    SectionTitle(month.header)
                        .textCase(nil)
                        .padding(.leading, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(28)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
    }
}
