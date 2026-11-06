import SwiftUI

/// The main call to action: 54 high, fully rounded, accent fill, 35% when disabled.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brFont(.navTitle)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Palette.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
    }
}

/// A quiet text button in accent, 48 high.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brFont(.navTitle)
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

/// A 1.5pt accent outline, radius 14, at least 50 high.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brFont(.navTitle)
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.accent, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}

/// Destructive actions: outlined by default, or filled for the final confirmation.
struct DestructiveButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .brFont(.navTitle)
            .foregroundStyle(filled ? Palette.onAccent : Palette.danger)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(filled ? Palette.danger : Color.clear, in: shape)
            .overlay(shape.strokeBorder(Palette.danger, lineWidth: filled ? 0 : 1.5))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var brPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var brSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
extension ButtonStyle where Self == OutlineButtonStyle {
    static var brOutline: OutlineButtonStyle { OutlineButtonStyle() }
}
extension ButtonStyle where Self == DestructiveButtonStyle {
    static var brDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
    static var brDestructiveFilled: DestructiveButtonStyle { DestructiveButtonStyle(filled: true) }
}
