import Foundation
import CryptoKit

enum CryptoError: LocalizedError {
    case notAStickPadFile
    case unsupportedVersion(UInt8)
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .notAStickPadFile:
            return "This file is not a Stick Pad store."
        case .unsupportedVersion(let v):
            return "This store was written by a newer version of Stick Pad (format \(v))."
        case .decryptionFailed:
            return "Could not decrypt your notes. The encryption key on this Mac does not match this store."
        }
    }
}

/// AES-256-GCM. Every write uses a fresh random nonce, and the GCM tag
/// authenticates both the ciphertext and the file header, so a tampered store
/// fails to open rather than silently returning altered notes.
enum CryptoBox {
    private static let magic: [UInt8] = Array("SPAD".utf8)
    private static let version: UInt8 = 1

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        var header = Data(magic)
        header.append(version)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = box.combined else { throw CryptoError.decryptionFailed }
        return header + combined
    }

    static func open(_ envelope: Data, key: SymmetricKey) throws -> Data {
        guard envelope.count > 5 else { throw CryptoError.notAStickPadFile }
        let header = envelope.prefix(5)
        guard Array(header.prefix(4)) == magic else { throw CryptoError.notAStickPadFile }
        let fileVersion = header[header.startIndex + 4]
        guard fileVersion == version else { throw CryptoError.unsupportedVersion(fileVersion) }

        let body = envelope.suffix(from: envelope.startIndex + 5)
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}
