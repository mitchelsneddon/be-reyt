import CryptoKit
import Foundation

/// Names of the encrypted photo blobs in the backup set. A blob is named by a keyed hash of its content, so the
/// folder never reveals which photos are identical to anything outside it, the same photo always lands on the same
/// name for one key (stored once), and a new key gives new names (no collisions between keys).
public enum BlobNaming {
    public static let keyBytes = 32

    /// `hex(HMAC-SHA256(dataKey, sha256(plaintext)))`, the SHA256 given as lowercase hex (64 characters).
    public static func name(dataKey: Data, plaintextSHA256: String) -> String? {
        guard dataKey.count == keyBytes, let digest = bytes(fromHex: plaintextSHA256), digest.count == 32
        else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(for: digest, using: SymmetricKey(data: dataKey))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// 64 lowercase hex characters, so a name taken from a manifest can never be a path.
    public static func isValidName(_ name: String) -> Bool {
        name.utf8.count == 64 && name.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// `blobs/{first 2}/{name}.aea`, relative to the backup folder.
    public static func relativePath(for name: String) -> String? {
        guard isValidName(name) else { return nil }
        return "\(folder)/\(name.prefix(2))/\(name).aea"
    }

    public static let folder = "blobs"

    /// The blob name inside an `{name}.aea` file name, or nil when it is not a blob file name.
    public static func name(fromFileName fileName: String) -> String? {
        guard fileName.hasSuffix(".aea") else { return nil }
        let stem = String(fileName.dropLast(4))
        return isValidName(stem) ? stem : nil
    }

    private static func bytes(fromHex hex: String) -> Data? {
        guard hex.utf8.count % 2 == 0 else { return nil }
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}
