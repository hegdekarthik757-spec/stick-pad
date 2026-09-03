import Foundation
import SwiftUI
import CryptoKit

/// Owns every note and the debounced write-back to the encrypted store.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    /// Set when the store on disk could not be decrypted. While this is non-nil
    /// saving is disabled so a key mismatch can never destroy existing notes.
    @Published private(set) var loadError: String?

    private var secure: SecureStore?
    private var attachments: AttachmentStore?
    private var key: SymmetricKey?
    private var saveWork: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.5

    var isReadOnly: Bool { loadError != nil }

    private struct LoadResult {
        var store: SecureStore?
        var attachments: AttachmentStore?
        var key: SymmetricKey?
        var notes: [Note] = []
        var error: String?
    }

    /// Unlocking touches the Keychain, and the Keychain can put an
    /// authorisation prompt on screen — which blocks its caller until the user
    /// answers. Doing that on the main thread launches the app into a frozen,
    /// window-less state, so the read happens off the main thread and the UI is
    /// populated when it returns.
    func bootstrap(completion: @escaping @MainActor () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = NoteStore.readStore()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.secure = result.store
                    self.attachments = result.attachments
                    self.key = result.key
                    self.notes = result.notes
                    self.loadError = result.error
                    // Images belonging to notes that no longer exist are
                    // dropped here rather than lingering on disk forever.
                    if result.error == nil { self.pruneOrphanedImages() }
                    completion()
                }
            }
        }
    }

    private nonisolated static func readStore() -> LoadResult {
        do {
            let key = try KeyStore.loadOrCreateKey()
            let store = SecureStore(key: key)
            let attachments = AttachmentStore(key: key,
                                              directory: SecureStore.defaultAttachmentsDirectory)
            let payload = try store.load()
            return LoadResult(store: store,
                              attachments: attachments,
                              key: key,
                              notes: payload.notes.sorted { $0.updatedAt > $1.updatedAt })
        } catch {
            return LoadResult(error: error.localizedDescription)
        }
    }

    /// Re-reads the store from disk, discarding whatever is in memory. Used
    /// after a key import or a restore.
    func reload(completion: @escaping @MainActor () -> Void) {
        cancelPendingSave()
        loadError = nil
        secure = nil
        attachments = nil
        key = nil
        notes = []
        bootstrap(completion: completion)
    }

    // MARK: - Backup and restore

    /// True when this Mac's key can open the given backup file.
    func canOpenBackup(at url: URL) -> Bool {
        secure?.canOpen(url) ?? false
    }

    /// Seals every note *and* every image into one portable file.
    func makeBackup() throws -> Data {
        guard let key else { throw ImageError.storeUnavailable }
        var images: [UUID: Data] = [:]
        for id in Set(notes.flatMap(\.imageIDs)) {
            if let data = try? attachments?.read(id: id) { images[id] = data }
        }
        return try BackupArchive.make(notes: notes, images: images, key: key)
    }

    /// Installs a backup over the live store and reloads. The caller is
    /// expected to have confirmed with the user first.
    func restore(fromBackupAt url: URL, completion: @escaping @MainActor () -> Void) throws {
        guard let secure, let attachments, let key else { throw ImageError.storeUnavailable }

        let contents = try BackupArchive.read(try Data(contentsOf: url), key: key)

        flush()                 // the pre-restore state becomes the .bak
        cancelPendingSave()     // and nothing queued may overwrite what we install

        try secure.save(notes: contents.notes)
        for (id, data) in contents.images {
            try attachments.write(data, id: id)
        }
        // Images belonging only to the replaced notes are no longer referenced.
        attachments.pruneOrphans(keeping: Set(contents.notes.flatMap(\.imageIDs)))

        ImageCache.shared.forget(Array(contents.images.keys))
        reload(completion: completion)
    }

    private func cancelPendingSave() {
        saveWork?.cancel()
        saveWork = nil
    }

    // MARK: - Lookup

    func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    var openNotes: [Note] { notes.filter(\.isOpen) }

    // MARK: - Mutation

    @discardableResult
    func createNote(color: String? = nil, near anchor: CGRect? = nil) -> Note {
        var note = Note()
        note.colorID = color ?? preferredNewColor()
        note.frame = NoteGeometry.frameForNewNote(near: anchor)
        notes.insert(note, at: 0)
        scheduleSave()
        return note
    }

    func upsert(_ note: Note) {
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            guard notes[i] != note else { return }
            notes[i] = note
        } else {
            notes.insert(note, at: 0)
        }
        scheduleSave()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        pruneOrphanedImages()
        scheduleSave()
    }

    func setOpen(_ isOpen: Bool, for id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].isOpen != isOpen else { return }
        notes[i].isOpen = isOpen
        scheduleSave()
    }

    /// The colour used for the next new note: keep using whatever the user last
    /// picked, so a chosen palette sticks.
    private func preferredNewColor() -> String {
        notes.max(by: { $0.updatedAt < $1.updatedAt })?.colorID ?? NotePalette.defaultColorID
    }

    // MARK: - Images

    /// Seals an image into its own attachment file and returns the id to store
    /// on the note line. The bytes are normalised first: rotated upright,
    /// downsampled, and re-encoded.
    func addImage(data: Data) throws -> (id: UUID, pixelSize: CGSize) {
        guard let attachments else { throw ImageError.storeUnavailable }
        guard !isReadOnly else { throw ImageError.storeLocked }
        guard let normalized = ImageImport.normalize(data: data) else { throw ImageError.unreadable }

        let id = UUID()
        try attachments.write(normalized.data, id: id)
        return (id, normalized.pixelSize)
    }

    func addImage(contentsOf url: URL) throws -> (id: UUID, pixelSize: CGSize) {
        guard let attachments else { throw ImageError.storeUnavailable }
        guard !isReadOnly else { throw ImageError.storeLocked }
        guard let normalized = ImageImport.normalize(contentsOf: url) else { throw ImageError.unreadable }

        let id = UUID()
        try attachments.write(normalized.data, id: id)
        return (id, normalized.pixelSize)
    }

    func imageData(for id: UUID) -> Data? {
        try? attachments?.read(id: id)
    }

    /// Deletes attachment files nothing points at any more.
    func pruneOrphanedImages() {
        guard let attachments, !isReadOnly else { return }
        let referenced = Set(notes.flatMap(\.imageIDs))
        attachments.pruneOrphans(keeping: referenced)
    }

    var imageBytesOnDisk: Int { attachments?.totalBytesOnDisk ?? 0 }

    // MARK: - Persistence

    func scheduleSave() {
        guard !isReadOnly else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard !isReadOnly, let secure else { return }
        do {
            try secure.save(notes: notes)
        } catch {
            NSLog("StickPad: save failed — \(error.localizedDescription)")
        }
    }

    var storeLocation: URL? { secure?.fileURL }
}
