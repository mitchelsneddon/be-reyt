import SwiftUI

/// The label of a settings row: tile, title, optional trailing value and status dot (before the value), and an
/// optional chevron for rows that open something without being a `NavigationLink`. Use inside a `Button`,
/// `NavigationLink` or `Toggle`; the row itself is at least 52pt high. `wrapping` is for sentence rows.
struct SettingsRowLabel: View {
    let title: String
    let icon: String
    var value: String?
    var dot: Color?
    var tint: IconTileStyle = .normal
    var wrapping = false
    var chevron = false
    @ScaledMetric(relativeTo: .body) private var chevronHeight: CGFloat = 13

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, style: tint)
            Text(title)
                .brFont(wrapping ? .rowWrapping : .row)
                .foregroundStyle(tint == .danger ? Palette.danger : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, wrapping ? 13 : 0)
            if value != nil || dot != nil {
                HStack(spacing: 6) {
                    if let dot { StatusDot(color: dot) }
                    if let value {
                        Text(value).brFont(.row).foregroundStyle(Palette.ink2).multilineTextAlignment(.trailing)
                    }
                }
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .resizable().scaledToFit()
                    .frame(width: chevronHeight * 0.6, height: chevronHeight)
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
