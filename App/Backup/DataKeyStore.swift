import Foundation
import ReytKit
import Security

/// The random 256-bit key that encrypts photo blobs in the backup set. Keychain, this device only, readable only
/// while the phone is unlocked. Generated at the first automatic backup, stored inside every snapshot too (so a new
/// phone recovers it from the passphrase), replaced when the passphrase changes, removed by delete-all.
struct DataKeyStore: Sendable {
    enum Failure: Error {
        case keychain(Int32)
        case randomFailed
    }

    private let service: String
    private let account = "backup-data-key"

    init(service: String = "local.mitchel.bereyt.backup") { self.service = service }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    #if DEBUG
        /// Simulator-only: unsigned simulator builds can't use the Keychain, so with `-debugPassphrase` the key lives
        /// in a file under the app's temp directory instead. Never compiled into release.
        private var debugFile: URL? {
            PassphraseStore.debugOverride == nil
                ? nil : FileManager.default.temporaryDirectory.appending(path: "debug-data-key.bin")
        }
    #endif

    /// nil only when there is no key (`errSecItemNotFound`); any other Keychain status throws, so a locked or
    /// failing Keychain can never be mistaken for "no key" and cause a new one to be generated.
    func current() throws -> Data? {
        #if DEBUG
            if let file = debugFile { return try? Data(contentsOf: file) }
        #endif
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = result as? Data, data.count == BlobNaming.keyBytes else { return nil }
        return data
    }

    /// The key, made on first use.
    func ensure() throws -> Data {
        if let key = try current() { return key }
        let key = try Self.generate()
        try store(key)
        return key
    }

    /// Keeps a key from a restored snapshot when this device has none.
    func adoptIfMissing(_ key: Data) throws {
        guard try current() == nil, key.count == BlobNaming.keyBytes else { return }
        try store(key)
    }

    /// A new key replaces the old one (passphrase change). Existing blobs stay readable by the old snapshots, which
    /// carry the old key; the next run writes every blob again under the new one.
    func rotate() throws {
        guard try current() != nil else { return }
        try store(try Self.generate())
    }

    func clear() {
        #if DEBUG
            if let file = debugFile { try? FileManager.default.removeItem(at: file) }
        #endif
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static func generate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: BlobNaming.keyBytes)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Failure.randomFailed
        }
        return Data(bytes)
    }

    private func store(_ key: Data) throws {
        #if DEBUG
            if let file = debugFile {
                try key.write(to: file)
                return
            }
        #endif
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: key] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.keychain(update) }
        var add = baseQuery
        add[kSecValueData as String] = key
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}
