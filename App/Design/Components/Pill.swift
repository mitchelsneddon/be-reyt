import SwiftUI

/// A small label pill: DM Sans 12/16 600, accentSoft fill, accentText text, radius 12.
struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .brFont(.pill)
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
