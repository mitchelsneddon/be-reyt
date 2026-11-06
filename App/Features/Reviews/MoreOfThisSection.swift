import ReytKit
import SwiftUI

/// "what would you like a little more of next week?": the reader's own words, optional, editable whenever the
/// review is open. Separate from the Sunday plan. Once saved it shows the real dates it was written for.
struct MoreOfThisSection: View {
    let model: ReviewModel
    let today: DateKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReflectionCard(
                question: Copy.Reviews.moreOfThisQuestion, helper: Copy.Reviews.moreOfThisHelper,
                answerLabel: Copy.Reviews.moreOfThisLabel,
                answer: Binding(get: { model.moreOfThisText }, set: { model.setMoreOfThis($0) }))
            if let start = model.targetStart, let end = model.targetEnd,
                !model.moreOfThisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(Copy.Reviews.moreOfThisTarget(DateRangeFormat.string(from: start, to: end, today: today)))
                    .font(.footnote).foregroundStyle(Palette.ink2)
            }
            if model.saveState == .failed {
                Button(Copy.Save.failed) { model.retry() }
                    .font(.footnote).foregroundStyle(Palette.accent).frame(minHeight: 44)
                    .accessibilityHint(Copy.Save.retryHint)
            }
        }
    }
}
