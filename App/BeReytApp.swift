import ReytKit
import SwiftUI

@main
struct BeReytApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
                SpikeView()
            #else
                RootPlaceholderView()
            #endif
        }
    }
}

struct RootPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("be reyt")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(Color("ink"))
            Text(ReytKit.tagline)
                .font(.footnote)
                .foregroundStyle(Color("inkSecondary"))
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("paper"))
        .accessibilityElement(children: .combine)
    }
}
