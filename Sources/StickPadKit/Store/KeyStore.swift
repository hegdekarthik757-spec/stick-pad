import Foundation
import Security
import CryptoKit

enum KeyStoreError: LocalizedError {
    case keychain(OSStatus)
    case badKeyMaterial

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(msg)"
        case .badKeyMaterial:
            return "That key is not a valid Stick Pad key (expected 32 bytes of base64)."
        }
    }
}

/// The note store is encrypted with a 256-bit key that never leaves this Mac
/// unless the user deliberately exports it. The key lives in the login Keychain
/// with `ThisDeviceOnly` protection, so it is not swept into an iCloud Keychain
/// backup and is unreadable while the Mac is locked.
enum KeyStore {
    static let service = "com.stickpad.notes"
    static let account = "master-key-v1"

    /// Returns the existing key, creating one on first launch.
    static func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try store(key)
        return key
    }

    static func loadKey() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { throw KeyStoreError.badKeyMaterial }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychain(status)
        }
    }

    /// Replaces whatever key is stored. Used on first launch and on key import.
    static func store(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrLabel as String] = "Stick Pad note encryption key"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
    }

    /// Base64 of the raw key. Shown once so the user can move it to another Mac
    /// (or keep it in a password manager as a recovery copy).
    static func exportKey() throws -> String {
        let key = try loadOrCreateKey()
        return key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    static func importKey(base64: String) throws {
        let cleaned = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleaned), data.count == 32 else {
            throw KeyStoreError.badKeyMaterial
        }
        try store(SymmetricKey(data: data))
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
