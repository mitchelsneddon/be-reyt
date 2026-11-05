import SwiftUI

/// The Sunday question: one short field plus optional single-select category chips. Shown on every Sunday page.
struct SundayPlanSection: View {
    @Environment(DayPageModel.self) private var model

    var body: some View {
        ReflectionCard(
            question: Copy.Plan.question, helper: Copy.Plan.helper, answerLabel: Copy.Plan.answerLabel,
            answer: Binding(get: { model.intentionText }, set: { model.setIntentionText($0) }),
            isEnabled: model.isLoaded, lineLimits: 1...3
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.Plan.categoriesLabel).font(.footnote).foregroundStyle(Color("inkSecondary"))
                ChipGroup(
                    items: Copy.Plan.categories.map { ChipItem(id: $0.id, label: $0.label) },
                    selection: Binding(
                        get: { model.intentionCategory.map { [$0] } ?? [] }, set: { _ in }),
                    allowsMultiple: false,
                    onToggle: { model.toggleIntentionCategory($0) })
            }
        }
    }
}
