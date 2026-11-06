import SwiftUI

/// A section heading in Playfair 23. Marked as a header for VoiceOver.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .brFont(.sectionTitle)
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}
