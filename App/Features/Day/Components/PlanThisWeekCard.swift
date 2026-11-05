import ReytKit
import SwiftUI

/// "your plan for this week": the Sunday plan whose target week contains this day, with a link to edit it.
/// Outside the current week it shows the real dates instead ("your plan for 9–15 nov").
struct PlanThisWeekCard: View {
    let plan: IntentionPlan
    let today: DateKey
    let onOpenSunday: (DateKey) -> Void

    private var title: String {
        if today >= plan.targetStart && today <= plan.targetEnd { return Copy.Plan.thisWeekTitle }
        return Copy.Plan.rangeTitle(DateRangeFormat.string(from: plan.targetStart, to: plan.targetEnd, today: today))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(Color("inkSecondary"))
                .accessibilityAddTraits(.isHeader)
            Text(plan.text).font(.body).foregroundStyle(Color("ink"))
            if let category = plan.category, !category.isEmpty {
                Text(Copy.Plan.categoryLabel(for: category)).font(.footnote).foregroundStyle(Color("inkSecondary"))
            }
            Button(Copy.Plan.editPlan) { onOpenSunday(plan.sourceSunday) }
                .font(.footnote)
                .foregroundStyle(Color("accent"))
                .frame(minHeight: 44)
                .accessibilityHint(Copy.Plan.editPlanHint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("hairline"), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
