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
    /// most editors render as real checkboxes. Image rows are linked when the
    /// caller has somewhere to put the picture files.
    static func text(for note: Note, format: ExportFormat,
                     imagePath: (UUID) -> String? = { _ in nil }) -> String {
        let body = note.lines.map { line -> String in
            if let imageID = line.imageID {
                let path = imagePath(imageID)
                switch format {
                case .markdown:
                    guard let path else { return "*(image)*" }
                    return "![image](\(escapeForLink(path)))"
                case .plainText:
                    guard let path else { return "[image]" }
                    return "[image: \(path)]"
                }
            }
            guard line.isCheckbox else { return line.text }
            let mark = line.isChecked ? "x" : " "
            switch format {
            case .markdown: return "- [\(mark)] \(line.text)"
            case .plainText: return "[\(mark)] \(line.text)"
            }
        }.joined(separator: "\n")
        return body.hasSuffix("\n") ? body : body + "\n"
    }

    static func data(for note: Note, format: ExportFormat,
                     imagePath: (UUID) -> String? = { _ in nil }) -> Data {
        Data(text(for: note, format: format, imagePath: imagePath).utf8)
    }

    private static func escapeForLink(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    /// PNG has a fixed 8-byte signature; anything else we write is JPEG.
    static func fileExtension(forImage data: Data) -> String {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.starts(with: png) ? "png" : "jpg"
    }

    static func imageFilename(id: UUID, data: Data) -> String {
        "\(id.uuidString.lowercased()).\(fileExtension(forImage: data))"
    }

    /// Writes one note, putting any images in a folder beside the file so the
    /// links in the exported text actually resolve.
    static func write(note: Note, to url: URL, format: ExportFormat,
                      imageData: (UUID) -> Data?) throws {
        var relativePaths: [UUID: String] = [:]

        let imageIDs = note.imageIDs
        if !imageIDs.isEmpty {
            let folderName = url.deletingPathExtension().lastPathComponent + " images"
            let folder = url.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
            var wroteAny = false
            for id in imageIDs {
                guard let data = imageData(id) else { continue }
                if !wroteAny {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    wroteAny = true
                }
                let name = imageFilename(id: id, data: data)
                try data.write(to: folder.appendingPathComponent(name), options: [.atomic])
                relativePaths[id] = "\(folderName)/\(name)"
            }
        }

        let text = data(for: note, format: format, imagePath: { relativePaths[$0] })
        try text.write(to: url, options: [.atomic])
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
                          folderName: String = "Stick Pad Notes",
                          imageData: (UUID) -> Data? = { _ in nil }) throws -> (folder: URL, count: Int) {
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

        // All the pictures go in one shared folder, keyed by attachment id so
        // two notes using the same image share a single file.
        var imagePaths: [UUID: String] = [:]
        let allImageIDs = notes.flatMap(\.imageIDs)
        if !allImageIDs.isEmpty {
            let imageFolder = folder.appendingPathComponent("images", isDirectory: true)
            var wroteAny = false
            for id in Set(allImageIDs) {
                guard let data = imageData(id) else { continue }
                if !wroteAny {
                    try fm.createDirectory(at: imageFolder, withIntermediateDirectories: true)
                    wroteAny = true
                }
                let name = imageFilename(id: id, data: data)
                try data.write(to: imageFolder.appendingPathComponent(name), options: [.atomic])
                imagePaths[id] = "images/\(name)"
            }
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
            try data(for: note, format: format, imagePath: { imagePaths[$0] }).write(to: url, options: [.atomic])
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
