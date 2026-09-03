import Foundation
import UniformTypeIdentifiers

/// Formats a note can be saved as. Both are plain, readable text — saving a
/// note this way deliberately puts a copy *outside* the encrypted store.
enum ExportFormat: CaseIterable {
    case markdown
    case plainText

    var displayName: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .plainText: return "Plain Text (.txt)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .plainText: return .plainText
        }
    }
}

enum ExportError: LocalizedError {
    case noNotes
    case couldNotCreateFolder(String)

    var errorDescription: String? {
        switch self {
        case .noNotes:
            return "There are no notes to save yet."
        case .couldNotCreateFolder(let path):
            return "Could not create a folder at \(path)."
        }
    }
}

enum NoteExporter {
    /// Checklist rows survive the trip: Markdown uses task-list syntax, which
    /// most editors render as real checkboxes.
    static func text(for note: Note, format: ExportFormat) -> String {
        let body = note.lines.map { line -> String in
            guard line.isCheckbox else { return line.text }
            let mark = line.isChecked ? "x" : " "
            switch format {
            case .markdown: return "- [\(mark)] \(line.text)"
            case .plainText: return "[\(mark)] \(line.text)"
            }
        }.joined(separator: "\n")
        return body.hasSuffix("\n") ? body : body + "\n"
    }

    static func data(for note: Note, format: ExportFormat) -> Data {
        Data(text(for: note, format: format).utf8)
    }

    /// A filename that is legal on macOS, readable, and never hidden.
    static func filename(for note: Note) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        var name = note.title.components(separatedBy: illegal).joined(separator: " ")
        name = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.count > 60 {
            name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? "Note" : name
    }

    /// Writes one file per note into a new folder inside `directory`, so an
    /// export can never overwrite something already sitting there.
    @discardableResult
    static func exportAll(_ notes: [Note], into directory: URL,
                          format: ExportFormat = .markdown,
                          folderName: String = "Stick Pad Notes") throws -> (folder: URL, count: Int) {
        guard !notes.isEmpty else { throw ExportError.noNotes }

        let fm = FileManager.default
        var folder = directory.appendingPathComponent(folderName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: folder.path) {
            folder = directory.appendingPathComponent("\(folderName) \(suffix)", isDirectory: true)
            suffix += 1
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw ExportError.couldNotCreateFolder(folder.path)
        }

        // Two notes can easily share a title, so names are made unique.
        var used = Set<String>()
        for note in notes {
            let base = filename(for: note)
            var candidate = base
            var n = 2
            while used.contains(candidate.lowercased()) {
                candidate = "\(base) \(n)"
                n += 1
            }
            used.insert(candidate.lowercased())

            let url = folder.appendingPathComponent(candidate).appendingPathExtension(format.fileExtension)
            try data(for: note, format: format).write(to: url, options: [.atomic])
        }
        return (folder, notes.count)
    }

    /// "Stick Pad Backup 2026-09-01.spad"
    static func backupFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Stick Pad Backup \(formatter.string(from: date)).spad"
    }
}
