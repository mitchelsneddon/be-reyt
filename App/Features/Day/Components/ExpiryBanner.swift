import SwiftUI

/// Calm reminder that the free-team install is about to expire.
struct ExpiryBanner: View {
    let daysLeft: Int

    var body: some View {
        Text(Copy.Banner.expiry(daysLeft: daysLeft))
            .font(.footnote)
            .foregroundStyle(Color("ink"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("accent"), lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color("paper"))
    }
}
