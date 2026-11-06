import SwiftUI

/// The Sunday question: one short field plus optional single-select category chips. Shown on every Sunday page.
struct SundayPlanSection: View {
    @Environment(DayPageModel.self) private var model

    var body: some View {
        ReflectionCard(
            question: Copy.Plan.question, answerLabel: Copy.Plan.answerLabel,
            answer: Binding(get: { model.intentionText }, set: { model.setIntentionText($0) }),
            isEnabled: model.isLoaded, lineLimits: 1...3,
            onFocusChange: { model.setFocus(.intention, $0) },
            action: {
                FlowLayout(spacing: 8) {
                    ForEach(Copy.Plan.categories, id: \.id) { category in
                        PlanCategoryChip(
                            label: category.label, isSelected: model.intentionCategory == category.id
                        ) { model.toggleIntentionCategory(category.id) }
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Copy.Plan.categoriesLabel)
            })
    }
}

/// A category chip: chip fill and ink2 at rest; accentSoft with a 1.5 inset accent ring when selected.
private struct PlanCategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .brFont(isSelected ? .chipSelected : .chip)
                .foregroundStyle(isSelected ? Palette.accentText : Palette.ink2)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    isSelected ? Palette.accentSoft : Palette.chip,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 1.5)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
