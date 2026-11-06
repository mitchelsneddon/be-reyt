import SwiftUI

/// The one way to size an SF Symbol: points at the default Dynamic Type size, scaling with `relativeTo`.
/// `maxPoints` caps growth where a symbol sits inside a fixed-shape disc or field.
private struct SymbolSizeModifier: ViewModifier {
    let weight: Font.Weight
    @ScaledMetric private var size: CGFloat
    private let maxPoints: CGFloat?

    init(_ points: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle, maxPoints: CGFloat?) {
        self.weight = weight
        self.maxPoints = maxPoints
        _size = ScaledMetric(wrappedValue: points, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(size, maxPoints ?? .infinity), weight: weight))
    }
}

extension View {
    func symbolSize(
        _ points: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body,
        maxPoints: CGFloat? = nil
    ) -> some View {
        modifier(SymbolSizeModifier(points, weight: weight, relativeTo: style, maxPoints: maxPoints))
    }
}
