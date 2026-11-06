import ReytKit
import SwiftUI
import UIKit

/// The only place colour-asset names are spelled. Everything else uses `Palette.x`.
enum Palette {
    static let paper = Color("paper")
    static let card = Color("card")
    static let ink = Color("ink")
    static let ink2 = Color("ink2")
    static let ink3 = Color("ink3")
    static let chip = Color("chip")
    static let border = Color("border")
    static let accent = Color("accent")
    static let accentText = Color("accentText")
    static let accentSoft = Color("accentSoft")
    static let onAccent = Color("onAccent")
    static let danger = Color("danger")
    static let dangerSoft = Color("dangerSoft")
    static let ok = Color("ok")
    static let warn = Color("warn")
    static let faceInk = Color("faceInk")
    static let polaroid = Color("polaroid")
    static let tape = Color("tape")
    /// The gold dot in the onboarding wordmark. The same in light and dark, so it is not an asset.
    static let wordmarkDot = Color(red: 0xD9 / 255, green: 0xA5 / 255, blue: 0x4A / 255)
    static let score1 = Color("score1")
    static let score2 = Color("score2")
    static let score3 = Color("score3")
    static let score4 = Color("score4")
    static let score5 = Color("score5")

    /// The calm five-step colour ramp for a day score.
    static func score(_ score: DayScore) -> Color {
        switch score {
        case .veryDifficult: score1
        case .difficult: score2
        case .okay: score3
        case .good: score4
        case .excellent: score5
        }
    }

    /// UIKit accessors for call sites that cannot take a SwiftUI `Color`.
    enum UI {
        static let paper = UIColor(named: "paper") ?? .systemBackground
        static let card = UIColor(named: "card") ?? .secondarySystemBackground
        static let ink = UIColor(named: "ink") ?? .label
        static let ink2 = UIColor(named: "ink2") ?? .secondaryLabel
        static let ink3 = UIColor(named: "ink3") ?? .tertiaryLabel
        static let border = UIColor(named: "border") ?? .separator
        static let accent = UIColor(named: "accent") ?? .tintColor
        static let accentSoft = UIColor(named: "accentSoft") ?? .secondarySystemFill
        static let accentText = UIColor(named: "accentText") ?? .label
        static let onAccent = UIColor(named: "onAccent") ?? .white

        static func score(_ score: DayScore) -> UIColor {
            UIColor(named: "score\(score.rawValue)") ?? .systemGray
        }
    }

    /// Shadow for polaroids and banners, resolved by colour scheme.
    struct Shadow: Sendable {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    static let polaroidShadow = Shadow(
        color: Color(
            uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0, alpha: 0.5)
                    : UIColor(red: 60 / 255, green: 40 / 255, blue: 20 / 255, alpha: 0.14)
            }),
        radius: 20, y: 8)

    /// Dimming layer behind modal spinners and covers.
    static let scrim = Color(
        uiColor: UIColor { trait in
            UIColor(white: 0, alpha: trait.userInterfaceStyle == .dark ? 0.5 : 0.25)
        })

    /// The photo viewer is always dark, whatever the system appearance.
    enum PhotoViewer {
        static let background = Color(red: 0x0E / 255, green: 0x0D / 255, blue: 0x0C / 255)
        static let text = Color(red: 0xEF / 255, green: 0xE8 / 255, blue: 0xDC / 255)
        static let secondary = Color(red: 0xA6 / 255, green: 0x9D / 255, blue: 0x90 / 255)
        static let circleButton = Color.white.opacity(0.12)
        static let remove = Color(red: 0xE5 / 255, green: 0x8C / 255, blue: 0x7E / 255)
    }
}

extension View {
    func polaroidShadow() -> some View {
        shadow(
            color: Palette.polaroidShadow.color, radius: Palette.polaroidShadow.radius,
            x: 0, y: Palette.polaroidShadow.y)
    }
}
