import Foundation

/// A single row inside a note. A row is either free text or a checkbox item.
struct NoteLine: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String = ""
    var isCheckbox: Bool = false
    var isChecked: Bool = false

    init(id: UUID = UUID(), text: String = "", isCheckbox: Bool = false, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isCheckbox = isCheckbox
        self.isChecked = isChecked
    }
}

struct Note: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var lines: [NoteLine] = [NoteLine()]
    var colorID: String = NotePalette.defaultColorID
    /// Last window frame in screen coordinates, so a note reopens where it was left.
    var frame: CGRect? = nil
    /// Whether the panel is showing. Closing a note hides it; deleting removes it.
    var isOpen: Bool = true
    /// Float above other apps.
    var isPinned: Bool = true
    var fontSize: Double = 14
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var color: NoteColor { NotePalette.color(id: colorID) }

    /// First non-empty line, used in the notes list and window title.
    var title: String {
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "New note"
    }

    var preview: String {
        lines.dropFirst(lines.isEmpty ? 0 : 1)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var checkboxCount: Int { lines.filter(\.isCheckbox).count }
    var checkedCount: Int { lines.filter { $0.isCheckbox && $0.isChecked }.count }

    var isEffectivelyEmpty: Bool {
        lines.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func index(of lineID: UUID) -> Int? {
        lines.firstIndex { $0.id == lineID }
    }
}
