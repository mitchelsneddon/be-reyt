import ReytKit
import SwiftUI

/// "this week": the Sunday plan whose target week contains this day, with a link to edit it.
/// Outside the current week the eyebrow shows the real dates instead ("9–15 nov").
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
            Text(title).brFont(.eyebrow).foregroundStyle(Palette.ink2)
                .accessibilityAddTraits(.isHeader)
            Text(plan.text).brFont(.body).foregroundStyle(Palette.ink)
            if let category = plan.category, !category.isEmpty {
                Pill(text: Copy.Plan.categoryLabel(for: category)).padding(.top, 2)
            }
            Button(Copy.Plan.editPlan) { onOpenSunday(plan.sourceSunday) }
                .brFont(.label)
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
                .accessibilityHint(Copy.Plan.editPlanHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
        .accessibilityElement(children: .contain)
    }
}
