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
        edit { note in
            guard let i = note.index(of: id) else { return }
            if note.lines[i].isCheckbox {
                note.lines[i].isCheckbox = false
                note.lines[i].isChecked = false
                self.focus = FocusTarget(lineID: id, caret: .start)
                return
            }
            guard i > 0 else { return }
            let removed = note.lines.remove(at: i)
            let mergeOffset = note.lines[i - 1].text.count
            note.lines[i - 1].text += removed.text
            self.focus = FocusTarget(lineID: note.lines[i - 1].id, caret: .offset(mergeOffset))
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
            note.lines.removeAll { $0.isCheckbox && $0.isChecked }
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

    // MARK: - Appearance

    func setColor(_ id: String) { edit { $0.colorID = id } }
    func togglePinned() { edit(touch: false) { $0.isPinned.toggle() } }
    func setFontSize(_ size: Double) { edit(touch: false) { $0.fontSize = min(max(size, 10), 28) } }
    func recordFrame(_ frame: CGRect) { edit(touch: false) { $0.frame = frame } }
}
