import ReytKit
import SwiftUI

/// "how did that go?": shown on the Sunday that ends a plan's target week. Gentle and optional; a saved note
/// or skip collapses to one line with an "edit" affordance.
struct FollowUpCard: View {
    @Environment(DayPageModel.self) private var model
    let plan: IntentionPlan
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(Copy.Plan.followUpTitle)
            Text(Copy.Plan.followUpQuote(plan.text)).brFont(.pointItalic).foregroundStyle(Palette.ink2)
                .padding(.bottom, 8)
            if model.followUpIsCollapsed { collapsed } else { editing }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 18)
    }

    private var collapsed: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.followUpSkipped ? Copy.Plan.skipped : model.followUpNote)
                .brFont(.body).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(Copy.Plan.edit) { model.editFollowUp() }
                .brFont(.navAction).foregroundStyle(Palette.accent).frame(minHeight: 44)
        }
    }

    private var editing: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(
                "", text: Binding(get: { model.followUpNote }, set: { model.setFollowUpNote($0) }), axis: .vertical
            )
            .brFont(.body).foregroundStyle(Palette.ink)
            .lineLimit(1...4)
            .focused($focused)
            .onChange(of: focused) { _, isFocused in model.setFocus(.followUp, isFocused) }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            .brPlaceholder(Copy.Plan.followUpPlaceholder, show: model.followUpNote.isEmpty, inset: 14, top: 8)
            .background(Palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .accessibilityLabel(Copy.Plan.followUpNoteLabel)
            HStack(spacing: 10) {
                pill(Copy.Plan.done, filled: true, selected: false) { model.finishEditingFollowUp() }
                pill(Copy.Plan.skip, filled: false, selected: model.followUpSkipped) { model.skipFollowUp() }
                    .accessibilityHint(Copy.Plan.skipHint)
            }
        }
    }

    private func pill(_ title: String, filled: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .brFont(.followUpPill)
                .foregroundStyle(selected ? Palette.onAccent : (filled ? Palette.accentText : Palette.ink))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected ? Palette.accent : (filled ? Palette.accentSoft : Palette.chip),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
