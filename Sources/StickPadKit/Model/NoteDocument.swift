import SwiftUI

/// Where to put the caret when focus moves to a line.
enum Caret: Equatable {
    case start
    case end
    case offset(Int)
}

struct FocusTarget: Equatable {
    var lineID: UUID
    var caret: Caret
}

/// The editing model for one open note. Every mutation funnels through `edit`,
/// which stamps `updatedAt` and pushes the note back into the store.
@MainActor
final class NoteDocument: ObservableObject {
    @Published var note: Note { didSet { store?.upsert(note) } }
    @Published var focus: FocusTarget?

    private weak var store: NoteStore?
    /// Surfaces an image that could not be added, e.g. an unreadable file.
    @Published var imageError: String?
    private var needsImagePrune = false

    init(note: Note, store: NoteStore?) {
        self.note = note
        self.store = store
    }

    /// `touch: false` for changes the user would not call an edit — window
    /// moves, resizes, open/closed state.
    func edit(touch: Bool = true, _ body: (inout Note) -> Void) {
        var next = note
        body(&next)
        if touch { next.updatedAt = Date() }
        guard next != note else { return }
        note = next
    }

    // MARK: - Line editing

    func binding(forLine id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self, let i = self.note.index(of: id) else { return "" }
                return self.note.lines[i].text
            },
            set: { [weak self] newValue in
                self?.edit { note in
                    guard let i = note.index(of: id) else { return }
                    // Pasting multi-line text splits into real lines.
                    let parts = newValue.components(separatedBy: .newlines)
                    if parts.count > 1 {
                        note.lines[i].text = parts[0]
                        let template = note.lines[i]
                        let inserted = parts.dropFirst().map {
                            NoteLine(text: $0, isCheckbox: template.isCheckbox, isChecked: false)
                        }
                        note.lines.insert(contentsOf: inserted, at: i + 1)
                    } else {
                        note.lines[i].text = newValue
                    }
                }
            }
        )
    }

    func insertLine(after id: UUID) {
        edit { note in
            guard let i = note.index(of: id) else { return }
            let current = note.lines[i]
            // Enter on an empty checkbox row ends the list instead of adding
            // another empty checkbox — the familiar list-editor behaviour.
            if current.isCheckbox && current.text.isEmpty {
                note.lines[i].isCheckbox = false
                note.lines[i].isChecked = false
                self.focus = FocusTarget(lineID: current.id, caret: .start)
                return
            }
            let new = NoteLine(isCheckbox: current.isCheckbox)
            note.lines.insert(new, at: i + 1)
            self.focus = FocusTarget(lineID: new.id, caret: .start)
        }
    }

    /// Backspace at the very start of a line: unwrap a checkbox first, then
    /// merge into the line above.
    func backspaceAtStart(of id: UUID) {
        needsImagePrune = false
        edit { note in
            guard let i = note.index(of: id) else { return }
            if note.lines[i].isCheckbox {
                note.lines[i].isCheckbox = false
                note.lines[i].isChecked = false
                self.focus = FocusTarget(lineID: id, caret: .start)
                return
            }
            guard i > 0 else { return }
            // There is nothing to merge into an image, so backspacing against
            // one deletes the picture instead.
            if note.lines[i - 1].isImage {
                note.lines.remove(at: i - 1)
                self.focus = FocusTarget(lineID: id, caret: .start)
                self.needsImagePrune = true
                return
            }
            let removed = note.lines.remove(at: i)
            let mergeOffset = note.lines[i - 1].text.count
            note.lines[i - 1].text += removed.text
            self.focus = FocusTarget(lineID: note.lines[i - 1].id, caret: .offset(mergeOffset))
        }
        if needsImagePrune {
            needsImagePrune = false
            store?.pruneOrphanedImages()
        }
    }

    func moveFocus(from id: UUID, by delta: Int) {
        guard let i = note.index(of: id) else { return }
        let target = i + delta
        guard note.lines.indices.contains(target) else { return }
        focus = FocusTarget(lineID: note.lines[target].id, caret: delta < 0 ? .end : .start)
    }

    func toggleCheckbox(on id: UUID) {
        edit { note in
            guard let i = note.index(of: id) else { return }
            note.lines[i].isCheckbox.toggle()
            if !note.lines[i].isCheckbox { note.lines[i].isChecked = false }
        }
        focus = FocusTarget(lineID: id, caret: .end)
    }

    func setChecked(_ checked: Bool, on id: UUID) {
        edit { note in
            guard let i = note.index(of: id) else { return }
            note.lines[i].isChecked = checked
        }
    }

    func toggleCheckboxOnFocusedLine() {
        let id = focus?.lineID ?? note.lines.last?.id
        guard let id else { return }
        toggleCheckbox(on: id)
    }

    func deleteLine(_ id: UUID) {
        edit { note in
            guard let i = note.index(of: id), note.lines.count > 1 else { return }
            note.lines.remove(at: i)
            let target = max(0, i - 1)
            self.focus = FocusTarget(lineID: note.lines[target].id, caret: .end)
        }
    }

    func clearCompleted() {
        edit { note in
            note.lines.removeAll { $0.isCheckbox && $0.isChecked && !$0.isImage }
            if note.lines.isEmpty { note.lines = [NoteLine()] }
        }
    }

    /// Tapping the empty area below the last line starts writing there.
    func focusLastLine() {
        if let last = note.lines.last, last.text.isEmpty {
            focus = FocusTarget(lineID: last.id, caret: .end)
            return
        }
        edit { note in
            let new = NoteLine()
            note.lines.append(new)
            self.focus = FocusTarget(lineID: new.id, caret: .start)
        }
    }

    // MARK: - Images

    /// Inserts an image below `lineID`, or at the end when that is nil. An
    /// empty text row is left after it so there is always somewhere to type.
    func insertImage(data: Data, after lineID: UUID?) {
        guard let store else { return }
        do {
            guard data.count <= ImageError.maximumSourceBytes else {
                throw ImageError.tooLarge(data.count)
            }
            let added = try store.addImage(data: data)
            place(imageID: added.id, pixelSize: added.pixelSize, after: lineID)
        } catch {
            report(error)
        }
    }

    func insertImage(contentsOf url: URL, after lineID: UUID?) {
        guard let store else { return }
        do {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
            if let size, size > ImageError.maximumSourceBytes {
                throw ImageError.tooLarge(size)
            }
            let added = try store.addImage(contentsOf: url)
            place(imageID: added.id, pixelSize: added.pixelSize, after: lineID)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        imageError = error.localizedDescription
        NotificationCenter.default.post(name: .stickPadReportError, object: nil,
                                        userInfo: ["message": error.localizedDescription])
    }

    private func place(imageID: UUID, pixelSize: CGSize, after lineID: UUID?) {
        edit { note in
            let row = NoteLine(imageID: imageID, pixelSize: pixelSize)
            let insertAt: Int
            if let lineID, let i = note.index(of: lineID) {
                insertAt = i + 1
                // Dropping onto a blank row replaces it rather than leaving a gap.
                if !note.lines[i].isImage && note.lines[i].text.isEmpty {
                    note.lines.remove(at: i)
                    note.lines.insert(row, at: i)
                    self.ensureTrailingTextRow(&note)
                    return
                }
            } else {
                insertAt = note.lines.count
            }
            note.lines.insert(row, at: insertAt)
            self.ensureTrailingTextRow(&note)
        }
    }

    /// An image as the last row would leave nowhere to put the caret.
    private func ensureTrailingTextRow(_ note: inout Note) {
        if note.lines.last?.isImage ?? true {
            let row = NoteLine()
            note.lines.append(row)
            self.focus = FocusTarget(lineID: row.id, caret: .start)
        } else if let last = note.lines.last {
            self.focus = FocusTarget(lineID: last.id, caret: .end)
        }
    }

    func removeImage(_ lineID: UUID) {
        edit { note in
            guard let i = note.index(of: lineID), note.lines[i].isImage else { return }
            note.lines.remove(at: i)
            if note.lines.isEmpty { note.lines = [NoteLine()] }
        }
        // The attachment file goes as soon as nothing refers to it.
        store?.pruneOrphanedImages()
    }

    func imageData(for id: UUID) -> Data? { store?.imageData(for: id) }

    // MARK: - Appearance

    func setColor(_ id: String) { edit { $0.colorID = id } }
    func togglePinned() { edit(touch: false) { $0.isPinned.toggle() } }
    func setFontSize(_ size: Double) { edit(touch: false) { $0.fontSize = min(max(size, 10), 28) } }
    func recordFrame(_ frame: CGRect) { edit(touch: false) { $0.frame = frame } }
}
