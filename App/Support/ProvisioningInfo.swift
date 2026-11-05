import Foundation

/// Free-team installs expire after 7 days. Reads the embedded profile's `ExpirationDate` so Today can warn.
struct ProvisioningInfo: Equatable {
    var expirationDate: Date?

    static let warningWindow: TimeInterval = 2 * 24 * 60 * 60

    /// Whole days left (rounded up) when the expiry is within the warning window, else nil.
    /// `now` is injected so the rule is testable.
    func daysLeftIfExpiring(now: Date) -> Int? {
        guard let expirationDate else { return nil }
        let remaining = expirationDate.timeIntervalSince(now)
        guard remaining <= Self.warningWindow else { return nil }
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }

    /// nil expiry in the simulator and App Store style builds, which have no embedded profile.
    static func load(bundle: Bundle = .main) -> ProvisioningInfo {
        #if DEBUG
            let fake = UserDefaults.standard.integer(forKey: "fakeExpiryDays")
            if fake > 0 {
                return ProvisioningInfo(expirationDate: Date.now.addingTimeInterval(Double(fake) * 86_400 - 60))
            }
        #endif
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url)
        else { return ProvisioningInfo(expirationDate: nil) }
        return ProvisioningInfo(expirationDate: expiration(fromProfile: data))
    }

    /// The profile is CMS-signed, but the plist inside is plain XML, so slice it out by its markers.
    static func expiration(fromProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data[start.lowerBound..<end.upperBound]
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil),
            let dict = object as? [String: Any]
        else { return nil }
        return dict["ExpirationDate"] as? Date
    }
}
