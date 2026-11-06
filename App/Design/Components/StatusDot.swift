import SwiftUI

/// An 8pt status dot. Never the only carrier of meaning: pair it with text.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}
