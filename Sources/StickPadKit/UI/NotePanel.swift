import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    static let stickPadNewNote = Notification.Name("StickPadNewNote")
    static let stickPadDeleteNote = Notification.Name("StickPadDeleteNote")
    static let stickPadResetSize = Notification.Name("StickPadResetSize")
    static let stickPadOpenNote = Notification.Name("StickPadOpenNote")
    static let stickPadSaveNoteAs = Notification.Name("StickPadSaveNoteAs")
    static let stickPadAddImage = Notification.Name("StickPadAddImage")
    static let stickPadReportError = Notification.Name("StickPadReportError")
}

/// A note window. `nonactivatingPanel` + `.floating` is what keeps a note
/// visible and typable over whatever app is in front, without stealing the
/// frontmost app's focus when you click into it.
final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotePanelController: NSObject, NSWindowDelegate {
    let doc: NoteDocument
    let panel: NotePanel
    private weak var store: NoteStore?
    private var cancellables = Set<AnyCancellable>()
    private var isClosingForGood = false

    var noteID: UUID { doc.note.id }

    init(note: Note, store: NoteStore?) {
        self.doc = NoteDocument(note: note, store: store)
        self.store = store

        let frame = NoteGeometry.clampToScreens(
            note.frame ?? CGRect(origin: .zero, size: NoteGeometry.defaultSize)
        )
        panel = NotePanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.title = note.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NoteGeometry.minSize
        panel.backgroundColor = note.color.paperNS
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.identifier = NSUserInterfaceItemIdentifier("note-\(note.id.uuidString)")

        let host = NSHostingView(rootView: NoteView(doc: doc))
        host.frame = panel.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        applyLevel()
        if note.frame == nil { panel.setFrame(frame, display: false) }

        // Keep the window chrome in step with the note's own state.
        doc.$note
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }
                self.panel.title = note.title
                self.panel.backgroundColor = note.color.paperNS
                self.applyLevel(pinned: note.isPinned)
            }
            .store(in: &cancellables)
    }

    // MARK: - Presentation

    func show(makeKey: Bool = true) {
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    func focusFirstLine() {
        guard let first = doc.note.lines.first else { return }
        doc.focus = FocusTarget(lineID: first.id, caret: .end)
    }

    func resetToStandardSize() {
        var frame = panel.frame
        let size = NoteGeometry.defaultSize
        // Grow downward from the current top-left, the way a paper note would.
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(NoteGeometry.clampToScreens(frame), display: true, animate: true)
    }

    /// Closes the window and removes the note for good.
    func closePermanently() {
        isClosingForGood = true
        panel.close()
    }

    private func applyLevel(pinned: Bool? = nil) {
        let isPinned = pinned ?? doc.note.isPinned
        panel.level = isPinned ? .floating : .normal
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { recordFrame() }
    func windowDidResize(_ notification: Notification) { recordFrame() }

    func windowDidBecomeKey(_ notification: Notification) {
        AppDelegate.shared?.lastFocusedNoteID = noteID
    }

    func windowWillClose(_ notification: Notification) {
        recordFrame()
        if !isClosingForGood {
            store?.setOpen(false, for: noteID)
        }
        AppDelegate.shared?.panelDidClose(noteID: noteID)
    }

    private func recordFrame() {
        guard panel.isVisible else { return }
        doc.recordFrame(panel.frame)
    }
}
