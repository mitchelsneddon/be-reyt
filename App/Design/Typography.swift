import SwiftUI
import UIKit

/// The type scale. Call sites use `.brFont(.body)`; they never set tracking or line spacing.
enum BRFont: CaseIterable, Sendable {
    // Playfair Display
    case largeTitle, screenTitle, onboardingTitle, leadCard, sectionTitle, stat, bigStat
    case promptItalic, captionItalic, viewerCaption, weekRow, dayNum, wordmark
    // Lora
    case body, bodyItalic, bodyItalicTight, point, pointItalic, rowTitle, rowSnippet
    // DM Sans
    case navTitle, navAction, navActionBold, row, rowWrapping, cardTitle, sectionHeader
    case eyebrow, label, labelBold, faceLabel, faceLabelBold, subhead, chip, pill

    // PostScript names, verified against the bundled TTFs.
    enum Face {
        static let playfairMedium = "PlayfairDisplay-Medium"
        static let playfairItalic = "PlayfairDisplay-Italic"
        static let playfairMediumItalic = "PlayfairDisplay-MediumItalic"
        static let loraRegular = "Lora-Regular"
        static let loraMedium = "Lora-Medium"
        static let loraItalic = "Lora-Italic"
        static let dmRegular = "DMSans-Regular"
        static let dmMedium = "DMSans-Medium"
        static let dmSemiBold = "DMSans-SemiBold"

        static let all = [
            playfairMedium, playfairItalic, playfairMediumItalic, loraRegular, loraMedium,
            loraItalic, dmRegular, dmMedium, dmSemiBold,
        ]
    }

    struct Spec {
        let name: String
        let size: CGFloat
        let line: CGFloat?
        let tracking: CGFloat
        let style: Font.TextStyle
    }

    var spec: Spec {
        switch self {
        case .largeTitle: Spec(name: Face.playfairMedium, size: 42, line: 50, tracking: -0.5, style: .largeTitle)
        case .screenTitle: Spec(name: Face.playfairMedium, size: 38, line: 46, tracking: -0.5, style: .largeTitle)
        case .onboardingTitle: Spec(name: Face.playfairMedium, size: 34, line: 42, tracking: 0, style: .title)
        case .leadCard: Spec(name: Face.playfairMedium, size: 28, line: 34, tracking: 0, style: .title2)
        case .sectionTitle: Spec(name: Face.playfairMedium, size: 23, line: 30, tracking: 0, style: .title3)
        case .stat: Spec(name: Face.playfairMedium, size: 22, line: 28, tracking: 0, style: .title3)
        case .bigStat: Spec(name: Face.playfairMedium, size: 44, line: 48, tracking: 0, style: .largeTitle)
        case .promptItalic: Spec(name: Face.playfairMediumItalic, size: 20, line: 30, tracking: 0, style: .title3)
        case .captionItalic: Spec(name: Face.playfairItalic, size: 14, line: nil, tracking: 0, style: .footnote)
        case .viewerCaption: Spec(name: Face.playfairItalic, size: 24, line: nil, tracking: 0, style: .title2)
        case .weekRow: Spec(name: Face.playfairMedium, size: 19, line: 24, tracking: 0, style: .headline)
        case .dayNum: Spec(name: Face.playfairMedium, size: 26, line: 28, tracking: 0, style: .title2)
        case .wordmark: Spec(name: Face.playfairMediumItalic, size: 22, line: nil, tracking: 0, style: .title3)
        case .body: Spec(name: Face.loraRegular, size: 17, line: 30, tracking: 0, style: .body)
        case .bodyItalic: Spec(name: Face.loraItalic, size: 17, line: 30, tracking: 0, style: .body)
        case .bodyItalicTight: Spec(name: Face.loraItalic, size: 17, line: 27, tracking: 0, style: .body)
        case .point: Spec(name: Face.loraRegular, size: 16, line: 24, tracking: 0, style: .callout)
        case .pointItalic: Spec(name: Face.loraItalic, size: 16, line: 24, tracking: 0, style: .callout)
        case .rowTitle: Spec(name: Face.loraMedium, size: 16, line: 22, tracking: 0, style: .callout)
        case .rowSnippet: Spec(name: Face.loraRegular, size: 14, line: 20, tracking: 0, style: .subheadline)
        case .navTitle: Spec(name: Face.dmSemiBold, size: 17, line: nil, tracking: 0, style: .headline)
        case .navAction: Spec(name: Face.dmRegular, size: 17, line: nil, tracking: 0, style: .body)
        case .navActionBold: Spec(name: Face.dmSemiBold, size: 17, line: nil, tracking: 0, style: .body)
        case .row: Spec(name: Face.dmRegular, size: 16, line: nil, tracking: 0, style: .body)
        case .rowWrapping: Spec(name: Face.dmRegular, size: 15, line: 21, tracking: 0, style: .body)
        case .cardTitle: Spec(name: Face.dmSemiBold, size: 15, line: nil, tracking: 0, style: .subheadline)
        case .sectionHeader: Spec(name: Face.dmRegular, size: 13, line: nil, tracking: 0.4, style: .footnote)
        case .eyebrow: Spec(name: Face.dmRegular, size: 13, line: nil, tracking: 0.6, style: .footnote)
        case .label: Spec(name: Face.dmRegular, size: 13, line: nil, tracking: 0, style: .footnote)
        case .labelBold: Spec(name: Face.dmSemiBold, size: 13, line: nil, tracking: 0, style: .footnote)
        case .faceLabel: Spec(name: Face.dmRegular, size: 12, line: 15, tracking: 0, style: .caption)
        case .faceLabelBold: Spec(name: Face.dmSemiBold, size: 12, line: 15, tracking: 0, style: .caption)
        case .subhead: Spec(name: Face.dmSemiBold, size: 13, line: 18, tracking: 0.4, style: .footnote)
        case .chip: Spec(name: Face.dmMedium, size: 14, line: nil, tracking: 0, style: .subheadline)
        case .pill: Spec(name: Face.dmSemiBold, size: 12, line: 16, tracking: 0, style: .caption)
        }
    }

    #if DEBUG
        /// Call once at launch: every bundled face must resolve by PostScript name.
        static func assertAllFontsRegistered() {
            for name in Face.all {
                assert(UIFont(name: name, size: 12) != nil, "font not registered: \(name)")
            }
        }
    #endif
}

private struct BRFontModifier: ViewModifier {
    let spec: BRFont.Spec
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var line: CGFloat

    init(_ style: BRFont) {
        let spec = style.spec
        self.spec = spec
        _size = ScaledMetric(wrappedValue: spec.size, relativeTo: spec.style)
        _line = ScaledMetric(wrappedValue: spec.line ?? 0, relativeTo: spec.style)
    }

    private var lineSpacing: CGFloat {
        guard spec.line != nil else { return 0 }
        let natural = UIFont(name: spec.name, size: size)?.lineHeight ?? size
        return max(0, line - natural)
    }

    func body(content: Content) -> some View {
        content
            .font(.custom(spec.name, size: spec.size, relativeTo: spec.style))
            .tracking(spec.tracking)
            .lineSpacing(lineSpacing)
    }
}

extension View {
    func brFont(_ style: BRFont) -> some View {
        modifier(BRFontModifier(style))
    }
}
