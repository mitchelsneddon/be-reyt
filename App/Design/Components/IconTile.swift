import SwiftUI

/// The 30pt rounded tile behind a settings-row icon. Scales with Dynamic Type up to a cap so rows stay tidy.
enum IconTileStyle {
    case normal, danger

    var background: Color { self == .danger ? Palette.dangerSoft : Palette.accentSoft }
    var foreground: Color { self == .danger ? Palette.danger : Palette.accent }
}

struct IconTile<Content: View>: View {
    typealias Style = IconTileStyle

    let style: Style
    private let content: Content
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 30

    init(style: Style = .normal, @ViewBuilder glyph: () -> Content) {
        self.style = style
        self.content = glyph()
    }

    var body: some View {
        let side = min(scaledSide, 44)
        content
            .foregroundStyle(style.foreground)
            .frame(width: side, height: side)
            .background(style.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension IconTile where Content == SymbolGlyph {
    /// An SF Symbol tile, glyph 18pt.
    init(systemName: String, style: Style = .normal) {
        self.init(style: style) { SymbolGlyph(systemName: systemName) }
    }
}

extension IconTile {
    /// A tile around a custom glyph view.
    init(glyph: Content, style: Style = .normal) {
        self.init(style: style) { glyph }
    }
}

/// An SF Symbol at the tile's 18pt glyph size, scaling with Dynamic Type.
struct SymbolGlyph: View {
    let systemName: String
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 18

    var body: some View {
        Image(systemName: systemName).resizable().scaledToFit().frame(width: min(side, 26), height: min(side, 26))
    }
}
