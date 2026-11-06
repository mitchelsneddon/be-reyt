import SwiftUI

/// A centred busy state: a ring over a line of text, for the restore, import and backup flows.
struct FlowBusy<Extra: View>: View {
    let text: String
    var serif = false
    private let extra: Extra

    init(_ text: String, serif: Bool = false, @ViewBuilder extra: () -> Extra) {
        self.text = text
        self.serif = serif
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 18) {
            ProgressRing(size: serif ? 40 : 32, lineWidth: 3)
            Text(text)
                .brFont(serif ? .dayNum : .rowWrapping)
                .foregroundStyle(serif ? Palette.ink : Palette.ink2)
                .multilineTextAlignment(.center)
            extra
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension FlowBusy where Extra == EmptyView {
    init(_ text: String, serif: Bool = false) { self.init(text, serif: serif) { EmptyView() } }
}

/// A centred disc (accentSoft or chip) with a glyph, over a line of text and optional content below.
struct FlowNotice<Below: View>: View {
    let icon: String
    let text: String
    var disc: Color = Palette.accentSoft
    var tint: Color = Palette.accent
    var side: CGFloat = 76
    var prominent = false
    private let below: Below
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(
        icon: String, text: String, disc: Color = Palette.accentSoft, tint: Color = Palette.accent,
        side: CGFloat = 76, prominent: Bool = false, @ViewBuilder below: () -> Below
    ) {
        self.prominent = prominent
        self.icon = icon
        self.text = text
        self.disc = disc
        self.tint = tint
        self.side = side
        self.below = below()
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .resizable().scaledToFit()
                .frame(width: side * 0.45 * min(scale, 1.5), height: side * 0.45 * min(scale, 1.5))
                .foregroundStyle(tint)
                .frame(width: side * min(scale, 1.5), height: side * min(scale, 1.5))
                .background(disc, in: Circle())
                .accessibilityHidden(true)
            Text(text).brFont(prominent ? .navAction : .rowWrapping)
                .foregroundStyle(prominent ? Palette.ink : Palette.ink2).multilineTextAlignment(.center)
            below
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension FlowNotice where Below == EmptyView {
    init(
        icon: String, text: String, disc: Color = Palette.accentSoft, tint: Color = Palette.accent,
        side: CGFloat = 76, prominent: Bool = false
    ) {
        self.init(icon: icon, text: text, disc: disc, tint: tint, side: side, prominent: prominent) { EmptyView() }
    }
}

/// A form field: a section-header style label over a 52 high, radius 14 secure field. `invalid` draws the border
/// in danger. The caller shows the error line.
struct BRSecureField: View {
    let label: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).brFont(.sectionHeader).foregroundStyle(Palette.ink2)
            SecureField("", text: $text)
                .textContentType(contentType)
                .brFont(.navAction)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(invalid ? Palette.danger : Palette.border, lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }
}

/// A one-line problem: a danger icon and the message, in danger.
struct ProblemLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").accessibilityLabel(Copy.Settings.problem)
            Text(text)
        }
        .brFont(.banner).foregroundStyle(Palette.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A flow sheet's title in the navigation bar, DM Sans 17 semibold.
struct FlowTitle: ToolbarContent {
    let text: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(text).brFont(.navTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
        }
    }
}
