import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    let store = NoteStore()
    private var panels: [UUID: NotePanelController] = [:]
    private var listController: NotesListWindowController?
    private var statusItem: NSStatusItem?
    var lastFocusedNoteID: UUID?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)

        MainMenu.install()
        installStatusItem()
        registerNotifications()
        unlock()
    }

    /// Reads the encrypted store. If the Keychain needs to ask the user for
    /// permission this can take a while, so a small notice appears rather than
    /// leaving the screen empty.
    private func unlock() {
        let notice = UnlockNotice()
        notice.showAfterDelay()

        store.bootstrap { [weak self] in
            notice.dismiss()
            guard let self else { return }
            if let error = self.store.loadError {
                self.presentLockedAlert(error)
                self.showNotesList()
                return
            }
            self.restoreOpenNotes()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in panels.values {
            controller.doc.recordFrame(controller.panel.frame)
        }
        store.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panels.isEmpty && listController?.window.isVisible != true {
            if store.notes.isEmpty { newNote(nil) } else { showNotesList() }
        } else {
            bringNotesToFront(nil)
        }
        return true
    }

    private func restoreOpenNotes() {
        let toOpen = store.notes.filter(\.isOpen)
        if toOpen.isEmpty && store.notes.isEmpty {
            newNote(nil)
            return
        }
        guard !toOpen.isEmpty else {
            // Every note is closed: show the list rather than launching to nothing.
            showNotesList()
            return
        }
        for note in toOpen.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            openPanel(for: note, makeKey: false)
        }
    }

    private func registerNotifications() {
        let center = NotificationCenter.default
        center.addObserver(forName: .stickPadNewNote, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.newNote(nil) }
        }
        center.addObserver(forName: .stickPadDeleteNote, object: nil, queue: .main) { note in
            guard let id = note.userInfo?["id"] as? UUID else { return }
            MainActor.assumeIsolated { self.confirmDelete(id: id) }
        }
        center.addObserver(forName: .stickPadResetSize, object: nil, queue: .main) { note in
            guard let id = note.userInfo?["id"] as? UUID else { return }
            MainActor.assumeIsolated { self.panels[id]?.resetToStandardSize() }
        }
        center.addObserver(forName: .stickPadOpenNote, object: nil, queue: .main) { note in
            guard let id = note.userInfo?["id"] as? UUID else { return }
            MainActor.assumeIsolated { self.openNote(id: id) }
        }
        center.addObserver(forName: .stickPadSaveNoteAs, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.saveFrontNoteAs(nil) }
        }
        center.addObserver(forName: .stickPadAddImage, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.addImageToFrontNote(nil) }
        }
        center.addObserver(forName: .stickPadReportError, object: nil, queue: .main) { note in
            guard let message = note.userInfo?["message"] as? String else { return }
            MainActor.assumeIsolated { self.presentMessage("Couldn't add that image", message) }
        }
    }

    // MARK: - Note windows

    @discardableResult
    private func openPanel(for note: Note, makeKey: Bool) -> NotePanelController {
        if let existing = panels[note.id] {
            existing.show(makeKey: makeKey)
            return existing
        }
        let controller = NotePanelController(note: note, store: store)
        panels[note.id] = controller
        controller.show(makeKey: makeKey)
        store.setOpen(true, for: note.id)
        return controller
    }

    func panelDidClose(noteID: UUID) {
        panels.removeValue(forKey: noteID)
        if lastFocusedNoteID == noteID { lastFocusedNoteID = nil }
    }

    private func openNote(id: UUID) {
        guard let note = store.note(id: id) else { return }
        let controller = openPanel(for: note, makeKey: true)
        controller.panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Deleting is the one destructive action here, so it always asks first —
    /// as a sheet on the note itself when that note is on screen.
    private func confirmDelete(id: UUID) {
        guard let note = store.note(id: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(note.title)”?"
        alert.informativeText = "This note will be removed permanently. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        let host = panels[id]?.panel ?? listController?.window
        if let host, host.isVisible {
            alert.beginSheetModal(for: host) { response in
                MainActor.assumeIsolated {
                    if response == .alertFirstButtonReturn { self.deleteNote(id: id) }
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            deleteNote(id: id)
        }
    }

    private func deleteNote(id: UUID) {
        panels[id]?.closePermanently()
        panels.removeValue(forKey: id)
        store.delete(id: id)
    }

    private var frontmostController: NotePanelController? {
        if let key = NSApp.keyWindow as? NotePanel,
           let match = panels.values.first(where: { $0.panel === key }) {
            return match
        }
        if let id = lastFocusedNoteID, let match = panels[id] { return match }
        return panels.values.first
    }

    // MARK: - Menu actions

    @objc func newNote(_ sender: Any?) {
        guard !store.isReadOnly else { NSSound.beep(); return }
        let anchor = frontmostController?.panel.frame
        let note = store.createNote(near: anchor)
        let controller = openPanel(for: note, makeKey: true)
        NSApp.activate(ignoringOtherApps: true)
        controller.panel.makeKeyAndOrderFront(nil)
        controller.focusFirstLine()
    }

    @objc func showNotesList(_ sender: Any? = nil) {
        if listController == nil {
            listController = NotesListWindowController(store: store)
        }
        listController?.show()
    }

    @objc func closeFrontNote(_ sender: Any?) {
        if let window = NSApp.keyWindow {
            window.performClose(nil)
        } else {
            frontmostController?.panel.performClose(nil)
        }
    }

    @objc func toggleCheckboxOnFrontNote(_ sender: Any?) {
        frontmostController?.doc.toggleCheckboxOnFocusedLine()
    }

    @objc func togglePinOnFrontNote(_ sender: Any?) {
        frontmostController?.doc.togglePinned()
    }

    @objc func resetFrontNoteSize(_ sender: Any?) {
        frontmostController?.resetToStandardSize()
    }

    @objc func deleteFrontNote(_ sender: Any?) {
        guard let id = frontmostController?.noteID else { return }
        confirmDelete(id: id)
    }

    @objc func cycleFrontNoteColor(_ sender: Any?) {
        guard let doc = frontmostController?.doc else { return }
        doc.setColor(NotePalette.next(after: doc.note.colorID))
    }

    @objc func bringNotesToFront(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        for controller in panels.values { controller.panel.orderFront(nil) }
    }

    @objc func hideAllNotes(_ sender: Any?) {
        for controller in panels.values { controller.panel.performClose(nil) }
    }

    @objc func showAllNotes(_ sender: Any?) {
        for note in store.notes where !note.isOpen {
            openPanel(for: note, makeKey: false)
        }
        bringNotesToFront(nil)
    }

    @objc func addImageToFrontNote(_ sender: Any?) {
        guard let controller = frontmostController else { NSSound.beep(); return }
        guard !store.isReadOnly else {
            presentError(ImageError.storeLocked)
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ImageImport.acceptedTypes
        panel.prompt = "Add"
        panel.message = "Images are encrypted alongside your notes."

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let target = controller.doc.focus?.lineID
            for url in panel.urls {
                controller.doc.insertImage(contentsOf: url, after: target)
            }
        }

        if controller.panel.isVisible {
            panel.beginSheetModal(for: controller.panel) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(panel.runModal())
        }
    }

    // MARK: - Saving to a file

    /// Notes save themselves continuously into the encrypted store; this is for
    /// getting a readable copy out to a folder of the user's choosing.
    @objc func saveFrontNoteAs(_ sender: Any?) {
        guard let controller = frontmostController else { NSSound.beep(); return }
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        let accessory = SaveFormatAccessory()
        panel.accessoryView = accessory
        panel.allowedContentTypes = [accessory.format.contentType]
        panel.nameFieldStringValue = NoteExporter.filename(for: controller.doc.note)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "This saves a readable copy outside Stick Pad, so it will not be encrypted."
        accessory.onChange = { [weak panel] format in
            panel?.allowedContentTypes = [format.contentType]
        }

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try NoteExporter.write(note: controller.doc.note, to: url,
                                       format: accessory.format,
                                       imageData: { self.store.imageData(for: $0) })
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.presentError(error)
            }
        }

        if controller.panel.isVisible {
            panel.beginSheetModal(for: controller.panel) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(panel.runModal())
        }
    }

    @objc func exportAllNotes(_ sender: Any?) {
        guard !store.notes.isEmpty else {
            presentError(ExportError.noNotes)
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = "Choose where to save a folder of your notes as Markdown files. "
            + "They will be readable text, not encrypted."

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let ordered = store.notes.sorted { $0.updatedAt > $1.updatedAt }
            let result = try NoteExporter.exportAll(ordered, into: directory,
                                                    imageData: { self.store.imageData(for: $0) })
            NSWorkspace.shared.activateFileViewerSelecting([result.folder])
        } catch {
            presentError(error)
        }
    }

    @objc func saveEncryptedBackup(_ sender: Any?) {
        guard !store.notes.isEmpty else {
            presentError(ExportError.noNotes)
            return
        }
        store.flush()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = NoteExporter.backupFilename()
        panel.canCreateDirectories = true
        panel.message = "The backup stays encrypted. Opening it on another Mac also needs your "
            + "encryption key, which you can export from this menu."
        panel.message += " Images in your notes are included."

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try store.makeBackup().write(to: destination, options: [.atomic])
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            presentError(error)
        }
    }

    @objc func restoreEncryptedBackup(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let open = NSOpenPanel()
        open.canChooseFiles = true
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        open.prompt = "Choose Backup"
        open.message = "Choose a Stick Pad backup to restore."
        guard open.runModal() == .OK, let url = open.url else { return }

        guard store.canOpenBackup(at: url) else {
            let alert = NSAlert()
            alert.messageText = "That backup can't be opened"
            alert.informativeText = "This Mac's encryption key does not match that file, so restoring "
                + "it would leave you with notes you cannot read.\n\nIf the backup came from another "
                + "Mac, import that Mac's key first (Security > Import Encryption Key), then restore."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let confirm = NSAlert()
        confirm.messageText = "Replace your notes with this backup?"
        confirm.informativeText = "Every note currently in Stick Pad will be replaced by the contents "
            + "of the backup. The notes you have now are kept next to the store as notes.spad.bak."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Restore")
        confirm.addButton(withTitle: "Cancel")
        confirm.buttons.first?.hasDestructiveAction = true
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            for controller in panels.values { controller.closePermanently() }
            panels.removeAll()
            try store.restore(fromBackupAt: url) { [weak self] in
                guard let self else { return }
                if let error = self.store.loadError {
                    self.presentLockedAlert(error)
                } else {
                    self.restoreOpenNotes()
                }
            }
        } catch {
            presentError(error)
        }
    }

    // MARK: - Key management

    @objc func exportKey(_ sender: Any?) {
        do {
            let key = try KeyStore.exportKey()
            let alert = NSAlert()
            alert.messageText = "Your Encryption Key"
            alert.informativeText = """
            This key decrypts every Stick Pad note on this Mac. Anyone holding it can read your notes, \
            so store it in a password manager — not in a plain text file.

            To read the same notes on another Mac, copy your encrypted store there and import this key.
            """
            let field = NSTextField(wrappingLabelWithString: key)
            field.isSelectable = true
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.frame = NSRect(x: 0, y: 0, width: 360, height: 44)
            alert.accessoryView = field
            alert.addButton(withTitle: "Copy to Clipboard")
            alert.addButton(withTitle: "Done")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
            }
        } catch {
            presentError(error)
        }
    }

    @objc func importKey(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Import an Encryption Key"
        alert.informativeText = """
        Paste a Stick Pad key (44 characters of base64). This replaces the key on this Mac.

        Notes already stored here were encrypted with the current key — after importing, only a store \
        that matches the new key can be opened.
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "base64 key"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = field
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            store.flush()
            try KeyStore.importKey(base64: field.stringValue)
            for controller in panels.values { controller.closePermanently() }
            panels.removeAll()
            store.reload { [weak self] in
                guard let self else { return }
                if let error = self.store.loadError {
                    self.presentLockedAlert(error)
                } else {
                    self.restoreOpenNotes()
                }
            }
        } catch {
            presentError(error)
        }
    }

    @objc func revealStore(_ sender: Any?) {
        let url = store.storeLocation ?? SecureStore.defaultDirectory
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Stick Pad"
        alert.informativeText = """
        Encrypted sticky notes for the Mac.

        Notes are stored in a single AES-256-GCM encrypted file. The key is generated on this Mac \
        and kept in your login Keychain, protected as “this device only”. Nothing is uploaded anywhere.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Alerts

    private func presentLockedAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Your notes are locked"
        alert.informativeText = """
        \(message)

        Saving is paused so your encrypted store is not overwritten. Use Security ▸ Import Encryption Key… \
        to restore the key that matches this store.
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Import Key…")
        if alert.runModal() == .alertSecondButtonReturn {
            importKey(nil)
        }
    }

    private func presentMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Something went wrong"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Stick Pad")
        item.button?.toolTip = "Stick Pad"

        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(newNote(_:)), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "All Notes…", action: #selector(showNotesList(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show All Notes", action: #selector(showAllNotes(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save All Notes to a Folder…", action: #selector(exportAllNotes(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide All Notes", action: #selector(hideAllNotes(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stick Pad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
