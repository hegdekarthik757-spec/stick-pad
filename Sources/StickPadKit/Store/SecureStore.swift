import Foundation
import CryptoKit

/// On-disk shape of the encrypted payload. Versioned so the format can grow.
struct StorePayload: Codable {
    var schema: Int = 1
    var notes: [Note] = []
    var savedAt: Date = Date()
}

/// Reads and writes the single encrypted file that holds every note.
/// Nothing readable ever touches the disk: the JSON is sealed before the first
/// write and the plaintext exists only in memory.
struct SecureStore {
    let fileURL: URL
    private let key: SymmetricKey

    init(key: SymmetricKey, directory: URL? = nil) {
        self.key = key
        let dir = directory ?? SecureStore.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("notes.spad")
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StickPad", isDirectory: true)
    }

    var storeExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    func load() throws -> StorePayload {
        guard storeExists else { return StorePayload() }
        let envelope = try Data(contentsOf: fileURL)
        guard !envelope.isEmpty else { return StorePayload() }
        let plaintext = try CryptoBox.open(envelope, key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StorePayload.self, from: plaintext)
    }

    /// True when `url` is a store this key can actually open. Checked before a
    /// restore so a backup from a different key can't replace working notes.
    func canOpen(_ url: URL) -> Bool {
        guard let envelope = try? Data(contentsOf: url) else { return false }
        return (try? CryptoBox.open(envelope, key: key)) != nil
    }

    /// Puts a backup in place, keeping the current store as `.bak`.
    func replaceContents(withBackupAt url: URL) throws {
        let envelope = try Data(contentsOf: url)
        _ = try CryptoBox.open(envelope, key: key)  // refuse to install something unreadable
        backupCurrentFile()
        try envelope.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func backupCurrentFile() {
        guard storeExists else { return }
        let backup = fileURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: fileURL, to: backup)
    }

    func save(notes: [Note]) throws {
        var payload = StorePayload()
        payload.notes = notes
        payload.savedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(payload)
        let envelope = try CryptoBox.seal(plaintext, key: key)

        // Keep one generation of history: a bad write can never be the only copy.
        backupCurrentFile()
        try envelope.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
