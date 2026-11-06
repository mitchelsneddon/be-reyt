import SwiftUI

/// A question and a multiline answer, set inline on the paper (no card). Shared by the smile question, the
/// rotating prompt, and the Sunday plan and follow-up cards. `refresh` adds the 44 pt "another prompt" button on
/// the right of the heading; `action` is an optional trailing slot below the answer.
struct ReflectionCard<Action: View>: View {
    let question: String
    var helper: String?
    var answerLabel: String
    @Binding var answer: String
    var isEnabled = true
    var lineLimits: ClosedRange<Int> = 1...6
    /// Reports whether the answer field has focus (the day page treats any focused field as "busy").
    var onFocusChange: (Bool) -> Void = { _ in }
    var refresh: (() -> Void)?
    @ViewBuilder var action: () -> Action

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(question)
                    .brFont(.promptItalic)
                    .foregroundStyle(Palette.accent)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let refresh {
                    Button(action: refresh) {
                        SymbolGlyph(systemName: "arrow.clockwise")
                            .foregroundStyle(Palette.ink2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -12)
                    .padding(.vertical, -7)
                    .accessibilityLabel(Copy.Reflection.anotherPrompt)
                    .accessibilityHint(Copy.Reflection.anotherPromptHint)
                }
            }
            if let helper {
                Text(helper).brFont(.label).foregroundStyle(Palette.ink2).padding(.top, 4)
            }
            TextField("", text: $answer, axis: .vertical)
                .brFont(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(lineLimits)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in onFocusChange(isFocused) }
                .disabled(!isEnabled)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .brPlaceholder(Copy.Reflection.answerPlaceholder, show: answer.isEmpty)
                .accessibilityLabel(answerLabel)
            action()
        }
    }
}

extension ReflectionCard where Action == EmptyView {
    init(
        question: String, helper: String? = nil, answerLabel: String, answer: Binding<String>, isEnabled: Bool = true,
        lineLimits: ClosedRange<Int> = 1...6, onFocusChange: @escaping (Bool) -> Void = { _ in },
        refresh: (() -> Void)? = nil
    ) {
        self.init(
            question: question, helper: helper, answerLabel: answerLabel, answer: answer, isEnabled: isEnabled,
            lineLimits: lineLimits, onFocusChange: onFocusChange, refresh: refresh
        ) { EmptyView() }
    }
}

extension View {
    /// An italic ink2 placeholder drawn over an empty text field (a `TextField` prompt cannot take `brFont`).
    func brPlaceholder(_ text: String, show: Bool) -> some View {
        overlay(alignment: .topLeading) {
            if show {
                Text(text).brFont(.bodyItalic).foregroundStyle(Palette.ink2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
