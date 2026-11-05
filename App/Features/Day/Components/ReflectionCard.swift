import SwiftUI

/// A question, optional helper text and a multiline answer. Shared by the smile question, the rotating prompt,
/// and later the Sunday plan and follow-up cards. `action` is an optional trailing slot (e.g. "another prompt").
struct ReflectionCard<Action: View>: View {
    let question: String
    var helper: String?
    var answerLabel: String
    @Binding var answer: String
    var isEnabled = true
    var lineLimits: ClosedRange<Int> = 2...6
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.headline)
                .foregroundStyle(Color("ink"))
                .accessibilityAddTraits(.isHeader)
            if let helper {
                Text(helper).font(.footnote).foregroundStyle(Color("inkSecondary"))
            }
            TextField(Copy.Reflection.answerPlaceholder, text: $answer, axis: .vertical)
                .font(.body)
                .foregroundStyle(Color("ink"))
                .lineLimit(lineLimits)
                .disabled(!isEnabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("hairline"), lineWidth: 1))
                .accessibilityLabel(answerLabel)
            action()
        }
    }
}

extension ReflectionCard where Action == EmptyView {
    init(
        question: String, helper: String? = nil, answerLabel: String, answer: Binding<String>, isEnabled: Bool = true,
        lineLimits: ClosedRange<Int> = 2...6
    ) {
        self.init(
            question: question, helper: helper, answerLabel: answerLabel, answer: answer, isEnabled: isEnabled,
            lineLimits: lineLimits
        ) { EmptyView() }
    }
}
