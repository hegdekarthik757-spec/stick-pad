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
    private var saveWork: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.5

    var isReadOnly: Bool { loadError != nil }

    private struct LoadResult {
        var store: SecureStore?
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
                    self.notes = result.notes
                    self.loadError = result.error
                    completion()
                }
            }
        }
    }

    private nonisolated static func readStore() -> LoadResult {
        do {
            let key = try KeyStore.loadOrCreateKey()
            let store = SecureStore(key: key)
            let payload = try store.load()
            return LoadResult(store: store,
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
        notes = []
        bootstrap(completion: completion)
    }

    // MARK: - Backup and restore

    /// True when this Mac's key can open the given backup file.
    func canOpenBackup(at url: URL) -> Bool {
        secure?.canOpen(url) ?? false
    }

    /// Installs a backup over the live store and reloads. The caller is
    /// expected to have confirmed with the user first.
    func restore(fromBackupAt url: URL, completion: @escaping @MainActor () -> Void) throws {
        guard let secure else { throw ExportError.noNotes }
        flush()                 // the pre-restore state becomes the .bak
        cancelPendingSave()     // and nothing queued may overwrite what we install
        try secure.replaceContents(withBackupAt: url)
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
