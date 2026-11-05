import Foundation
import ReytKit
import Security

/// The backup passphrase, in the Keychain: this device only (never synced, never in a device backup), readable
/// only while the phone is unlocked. Device-local state, so a restore never replaces it.
struct PassphraseStore: Sendable {
    enum Failure: Error { case keychain(Int32) }

    static let minimumLength = 8

    private let service: String
    private let account = "backup-passphrase"

    init(service: String = "local.mitchel.bereyt.backup") { self.service = service }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    var hasPassphrase: Bool { stored() != nil }

    #if DEBUG
        /// Simulator-only: unsigned simulator builds can't use the Keychain, so `-debugPassphrase` lands here.
        nonisolated(unsafe) static var debugOverride: String?
    #endif

    func stored() -> String? {
        #if DEBUG
            if let override = Self.debugOverride { return override }
        #endif
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ passphrase: String) throws {
        let data = Data(passphrase.utf8)
        let update = SecItemUpdate(
            baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.keychain(update) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// The only rule: at least 8 characters (and short enough for the archive engine).
    static func isAcceptable(_ passphrase: String) -> Bool {
        passphrase.count >= minimumLength && passphrase.utf8.count <= ArchiveCrypto.maxPassphraseBytes
    }
}
