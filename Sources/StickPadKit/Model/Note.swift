import Foundation
import CoreGraphics

/// A single row inside a note: free text, a checkbox item, or an image.
///
/// The image fields are optional so that notes written before images existed
/// still decode — the synthesised decoder skips absent optional keys.
struct NoteLine: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String = ""
    var isCheckbox: Bool = false
    var isChecked: Bool = false

    /// Identifies the sealed attachment file holding this row's image.
    var imageID: UUID? = nil
    /// Pixel size of that image, kept here so a row can be laid out without
    /// decrypting and decoding the picture first.
    var imageWidth: Double? = nil
    var imageHeight: Double? = nil

    init(id: UUID = UUID(), text: String = "", isCheckbox: Bool = false, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isCheckbox = isCheckbox
        self.isChecked = isChecked
    }

    init(imageID: UUID, pixelSize: CGSize) {
        self.id = UUID()
        self.imageID = imageID
        self.imageWidth = Double(pixelSize.width)
        self.imageHeight = Double(pixelSize.height)
    }

    var isImage: Bool { imageID != nil }

    /// Falls back to a square when the stored size is missing or nonsense, so a
    /// damaged row still lays out instead of collapsing.
    var imagePixelSize: CGSize {
        guard let w = imageWidth, let h = imageHeight, w > 0, h > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: w, height: h)
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
        for line in lines where !line.isImage {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return hasImages ? "Image note" : "New note"
    }

    var hasImages: Bool { lines.contains { $0.isImage } }

    /// Every attachment this note refers to.
    var imageIDs: [UUID] { lines.compactMap(\.imageID) }

    var preview: String {
        lines.dropFirst(lines.isEmpty ? 0 : 1)
            .map { $0.isImage ? "Image" : $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var checkboxCount: Int { lines.filter(\.isCheckbox).count }
    var checkedCount: Int { lines.filter { $0.isCheckbox && $0.isChecked }.count }

    var isEffectivelyEmpty: Bool {
        lines.allSatisfy { !$0.isImage && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func index(of lineID: UUID) -> Int? {
        lines.firstIndex { $0.id == lineID }
    }
}
