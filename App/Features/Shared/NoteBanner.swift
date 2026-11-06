import SwiftUI

/// One calm, dismissable note at the top of the screen. Card surface with a polaroid shadow, radius 14, at least
/// 52 high, padding 4/4/4/14, with a 44pt dismiss button.
extension View {
    /// Places a banner at the top of a screen with the standard gutter.
    func noteBannerInset() -> some View { padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4) }
}

/// The restore and delete-all notes, drawn under the navigation bar of the tab that shows them. Both read the one
/// coordinator state from the environment, so there is no per-tab copy.
private struct CompletionNotes: ViewModifier {
    @Environment(RestoreCoordinator.self) private var restore
    @Environment(DeleteAllCoordinator.self) private var deleteAll

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let note = deleteAll.completionNote {
                    NoteBanner(
                        icon: deleteAll.completionIsPartial ? "exclamationmark.triangle" : "checkmark.circle",
                        text: note,
                        tint: deleteAll.completionIsPartial ? Palette.danger : Palette.ok,
                        dismiss: deleteAll.dismissCompletionNote
                    )
                    .noteBannerInset()
                }
                if let note = restore.completionNote {
                    NoteBanner(
                        icon: restore.completionIsUndo ? "arrow.uturn.backward" : "checkmark.circle",
                        text: note,
                        tint: restore.completionIsUndo ? Palette.accent : Palette.ok,
                        dismiss: restore.dismissCompletionNote
                    )
                    .noteBannerInset()
                }
            }
        }
    }
}

extension View {
    /// Shows the restore and delete-all notes under this screen's navigation bar. Apply to each tab's root content.
    func completionNotes() -> some View { modifier(CompletionNotes()) }
}

struct NoteBanner: View {
    let icon: String
    let text: String
    var tint: Color = Palette.accent
    var dismiss: (() -> Void)?
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
            if let dismiss {
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
        }
        .padding(.init(top: 4, leading: 14, bottom: dismiss == nil ? 12 : 4, trailing: dismiss == nil ? 14 : 4))
        .padding(.top, dismiss == nil ? 8 : 0)
        .frame(minHeight: 52)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .polaroidShadow()
        .accessibilityElement(children: .contain)
    }
}
