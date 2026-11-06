import ReytKit
import SwiftUI

/// "how did you feel today?": a grid of 56 pt mood tiles. Multi-select; each tile is a toggle button.
/// Retired moods show only when the day carried them at load (`loadedIDs`).
struct MoodTileGrid: View {
    let selected: [String]
    let loadedIDs: [String]
    let onToggle: (String) -> Void

    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 26
    @Environment(\.dynamicTypeSize) private var typeSize

    private var moods: [MoodCatalog.Mood] { MoodCatalog.offered(including: loadedIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(Copy.Day.feelTitle)
            if typeSize.isAccessibilitySize {
                FlowLayout(spacing: 12) {
                    ForEach(moods, id: \.id) { cell($0) }
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 5),
                    alignment: .center, spacing: 14
                ) {
                    ForEach(moods, id: \.id) { cell($0) }
                }
            }
        }
    }

    private func cell(_ mood: MoodCatalog.Mood) -> some View {
        let isOn = selected.contains(mood.id)
        let size = min(tile, 72)
        return Button {
            onToggle(mood.id)
        } label: {
            VStack(spacing: 8) {
                MoodGlyph(id: mood.id, size: min(glyph, 34))
                    .foregroundStyle(isOn ? Palette.accent : Palette.ink2)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isOn ? Palette.accentSoft : Palette.chip)
                    )
                    .overlay {
                        if isOn {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 1.5)
                        }
                    }
                Text(mood.label)
                    .brFont(isOn ? .labelBold : .label)
                    .foregroundStyle(isOn ? Palette.ink : Palette.ink2)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
