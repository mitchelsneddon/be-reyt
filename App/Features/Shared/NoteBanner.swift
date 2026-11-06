import SwiftUI

/// One calm, dismissable note at the top of the screen. Card surface with a polaroid shadow, radius 14, at least
/// 52 high, padding 4/4/4/14, with a 44pt dismiss button.
struct NoteBanner: View {
    let icon: String
    let text: String
    var tint: Color = Palette.accent
    let dismiss: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var closeSize: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .brFont(.banner)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .resizable().scaledToFit()
                    .frame(width: closeSize, height: closeSize)
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Copy.Shared.dismiss)
        }
        .padding(.init(top: 4, leading: 14, bottom: 4, trailing: 4))
        .frame(minHeight: 52)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .polaroidShadow()
        .accessibilityElement(children: .contain)
    }
}
