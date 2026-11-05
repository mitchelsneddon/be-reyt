import ReytKit
import SwiftData
import SwiftUI

@main
struct BeReytApp: App {
    @State private var host = ContainerHost()
    @State private var events = JournalEvents()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            content
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: host.openIfPossible()
                    case .background: host.protect()
                    default: break
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if let store = host.store, let container = host.container, let generation = host.generationID {
            RootView(store: store, events: events)
                .modelContainer(container)
                .id(generation)
        } else {
            WaitingView(failed: host.openFailed)
        }
    }
}

/// Shown until the container exists: the phone is still locked, or the store could not be opened.
private struct WaitingView: View {
    let failed: Bool

    var body: some View {
        Text(failed ? Copy.Host.openFailed : Copy.Host.unlockPhone)
            .font(.body)
            .foregroundStyle(Color("inkSecondary"))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("paper"))
    }
}
