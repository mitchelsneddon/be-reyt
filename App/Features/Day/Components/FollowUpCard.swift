import ReytKit
import SwiftUI

/// "how did that go?": shown on the Sunday that ends a plan's target week. Gentle and optional; a saved note
/// or skip collapses to one line with an "edit" affordance.
struct FollowUpCard: View {
    @Environment(DayPageModel.self) private var model
    let plan: IntentionPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.Plan.followUpTitle)
                .font(.headline).foregroundStyle(Color("ink"))
                .accessibilityAddTraits(.isHeader)
            Text(Copy.Plan.followUpQuote(plan.text)).font(.footnote).foregroundStyle(Color("inkSecondary"))
            if model.followUpIsCollapsed { collapsed } else { editing }
        }
    }

    private var collapsed: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.followUpSkipped ? Copy.Plan.skipped : model.followUpNote)
                .font(.body).foregroundStyle(Color("ink"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(Copy.Plan.edit) { model.editFollowUp() }
                .font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
        }
    }

    private var editing: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                Copy.Plan.followUpPlaceholder,
                text: Binding(get: { model.followUpNote }, set: { model.setFollowUpNote($0) }), axis: .vertical
            )
            .font(.body).foregroundStyle(Color("ink"))
            .lineLimit(1...4)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("hairline"), lineWidth: 1))
            .accessibilityLabel(Copy.Plan.followUpNoteLabel)
            HStack {
                Button(Copy.Plan.skip) { model.skipFollowUp() }
                    .accessibilityHint(Copy.Plan.skipHint)
                Spacer()
                if model.isEditingFollowUp {
                    Button(Copy.Plan.done) { model.finishEditingFollowUp() }
                }
            }
            .font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
        }
    }
}
