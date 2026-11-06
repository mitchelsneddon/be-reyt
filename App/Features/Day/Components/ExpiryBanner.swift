import SwiftUI

/// Calm reminder that the free-team install is about to expire.
struct ExpiryBanner: View {
    let daysLeft: Int

    var body: some View {
        NoteBanner(icon: "clock", text: Copy.Banner.expiry(daysLeft: daysLeft))
            .noteBannerInset()
    }
}
