import SwiftUI

/// The label of a settings row: tile, title, optional trailing value and status dot. Use inside a `Button`,
/// `NavigationLink` or `Toggle`; the row itself is at least 52pt high.
struct SettingsRowLabel: View {
    let title: String
    let icon: String
    var value: String?
    var dot: Color?
    var tint: IconTileStyle = .normal

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, style: tint)
            Text(title)
                .brFont(.row)
                .foregroundStyle(tint == .danger ? Palette.danger : Palette.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value).brFont(.row).foregroundStyle(Palette.ink2).multilineTextAlignment(.trailing)
            }
            if let dot { StatusDot(color: dot) }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
