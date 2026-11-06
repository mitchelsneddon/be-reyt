import SwiftUI

extension View {
    /// The card surface: `card` fill, radius 18, 1pt `border`. Default padding is the 20 used by flows.
    func cardSurface(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }
}
