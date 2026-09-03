import Foundation
import CryptoKit

/// A backup has to be self-contained. Notes live in `notes.spad` and images in
/// separate attachment files, so a backup that copied only the notes would
/// quietly lose every picture. This seals both into one file.
enum BackupArchive {
    struct Payload: Codable {
        var schema: Int = 2
        var notes: [Note] = []
        /// Attachment id (as a string, since JSON keys must be strings) to the
        /// decrypted image bytes. The whole payload is sealed afterwards.
        var images: [String: Data] = [:]
        var savedAt: Date = Date()
    }

    struct Contents {
        var notes: [Note]
        var images: [UUID: Data]
    }

    static func make(notes: [Note], images: [UUID: Data], key: SymmetricKey) throws -> Data {
        var payload = Payload()
        payload.notes = notes
        payload.images = Dictionary(uniqueKeysWithValues: images.map { ($0.key.uuidString, $0.value) })
        payload.savedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try CryptoBox.seal(try encoder.encode(payload), key: key)
    }

    /// Opens a backup. Files written before images existed hold a bare
    /// `StorePayload`, so those are still accepted.
    static func read(_ envelope: Data, key: SymmetricKey) throws -> Contents {
        let plaintext = try CryptoBox.open(envelope, key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let payload = try? decoder.decode(Payload.self, from: plaintext), payload.schema >= 2 {
            var images: [UUID: Data] = [:]
            for (key, value) in payload.images {
                if let id = UUID(uuidString: key) { images[id] = value }
            }
            return Contents(notes: payload.notes, images: images)
        }

        let legacy = try decoder.decode(StorePayload.self, from: plaintext)
        return Contents(notes: legacy.notes, images: [:])
    }
}
