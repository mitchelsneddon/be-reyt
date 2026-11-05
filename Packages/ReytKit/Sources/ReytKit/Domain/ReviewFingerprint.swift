import CryptoKit
import Foundation

/// `inputFingerprint = SHA256(canonical JSON of ReflectionInput)`. `promptVersion` is deliberately not part of it:
/// a newer prompt version offers "regenerate" and never purges.
public enum ReviewFingerprint {
    public static func canonicalJSON(_ input: ReflectionInput) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(input)
    }

    public static func compute(_ input: ReflectionInput) throws -> String {
        SHA256.hash(data: try canonicalJSON(input)).map { String(format: "%02x", $0) }.joined()
    }
}
