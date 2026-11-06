import SwiftUI
import UIKit

/// Keeps the end of a growing text field above the keyboard while typing at the end of it. Scrolls only when the
/// last line is behind the keyboard, so short entries never jump. The day page passes the keyboard's top edge in
/// global coordinates.
struct KeepAboveKeyboard: ViewModifier {
    /// Room left between the last line and the top of the keyboard.
    static let margin: CGFloat = 28

    let anchorID: String
    let text: String
    let isFocused: Bool
    /// Top of the keyboard in global coordinates; `.infinity` while it is hidden.
    let keyboardTop: CGFloat
    let proxy: ScrollViewProxy

    /// How long after a keystroke a layout change still counts as caused by typing (a new line wrapping), rather
    /// than by the user scrolling.
    static let typingWindow: Duration = .milliseconds(600)

    @State private var screenBottom: CGFloat = 0
    @State private var lastTypedAtEnd: ContinuousClock.Instant?

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            // The scroll target: a real (empty) view `margin` tall under the field, so the last line keeps room.
            Color.clear.frame(height: Self.margin).id(anchorID).accessibilityHidden(true)
        }
        .padding(.bottom, -Self.margin)
        .onChange(of: text) { old, new in
            // Only typing at the end (an append) follows; an edit further up stays where the caret is.
            guard new.count > old.count, new.hasPrefix(old) else { return }
            lastTypedAtEnd = .now
            scrollIfHidden()
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .global).maxY
        } action: { bottom in
            screenBottom = bottom
            guard let typed = lastTypedAtEnd, ContinuousClock.now - typed < Self.typingWindow else { return }
            scrollIfHidden()
        }
    }

    private func scrollIfHidden() {
        guard isFocused, screenBottom + Self.margin > keyboardTop else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(anchorID, anchor: .bottom) }
    }
}

extension View {
    /// Tracks the keyboard's top edge in global (screen) coordinates; `.infinity` while it is hidden.
    func trackingKeyboardTop(_ top: Binding<CGFloat>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            guard let frame = $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // A dismissed keyboard reports a frame below the screen, which never triggers a scroll.
            top.wrappedValue = frame.height > 0 ? frame.minY : .infinity
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            top.wrappedValue = .infinity
        }
    }
}
