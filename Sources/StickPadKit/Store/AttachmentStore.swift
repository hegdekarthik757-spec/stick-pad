import Foundation
import CryptoKit

/// Images live one-per-file, each sealed with the same key as the notes.
///
/// Keeping them out of `notes.spad` matters: the notes file is rewritten on a
/// debounce every time you type, and re-encrypting several megabytes of photos
/// on every keystroke would be unusable. An image is written once and then only
/// read.
struct AttachmentStore {
    static let fileExtension = "spadimg"

    let directory: URL
    private let key: SymmetricKey

    init(key: SymmetricKey, directory: URL) {
        self.key = key
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    func write(_ data: Data, id: UUID) throws {
        let envelope = try CryptoBox.seal(data, key: key)
        try envelope.write(to: url(for: id), options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url(for: id).path)
    }

    func read(id: UUID) throws -> Data {
        let envelope = try Data(contentsOf: url(for: id))
        return try CryptoBox.open(envelope, key: key)
    }

    func exists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    func allIDs() -> Set<UUID> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return Set(contents.compactMap { url -> UUID? in
            guard url.pathExtension == Self.fileExtension else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        })
    }

    /// Removes attachment files no note refers to any more — after a note is
    /// deleted, or an image removed from one.
    @discardableResult
    func pruneOrphans(keeping referenced: Set<UUID>) -> Int {
        let orphans = allIDs().subtracting(referenced)
        for id in orphans { delete(id: id) }
        return orphans.count
    }

    var totalBytesOnDisk: Int {
        allIDs().reduce(0) { running, id in
            let size = (try? FileManager.default.attributesOfItem(atPath: url(for: id).path)[.size]) as? Int
            return running + (size ?? 0)
        }
    }
}
