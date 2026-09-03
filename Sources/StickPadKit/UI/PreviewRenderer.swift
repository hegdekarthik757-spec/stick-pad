import AppKit
import SwiftUI

/// Renders a sample note straight to PNG without showing a window.
/// Used by `StickPad --render-preview <dir>` to eyeball the design in both
/// appearances during development.
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (name, appearance) in [("light", NSAppearance(named: .aqua)),
                                   ("dark", NSAppearance(named: .darkAqua))] {
            for color in ["butter", "sky", "rose"] where name == "light" || color == "butter" {
                let note = sampleNote(colorID: color)
                let data = render(note: note, appearance: appearance)
                let url = dir.appendingPathComponent("note-\(color)-\(name).png")
                try? data?.write(to: url)
            }
        }
        print("preview written to \(dir.path)")
    }

    private static func sampleNote(colorID: String) -> Note {
        var note = Note()
        note.colorID = colorID
        note.lines = [
            NoteLine(text: "Weekend"),
            NoteLine(text: "Book the ferry tickets before Friday", isCheckbox: true, isChecked: true),
            NoteLine(text: "Pick up the dry cleaning", isCheckbox: true, isChecked: true),
            NoteLine(text: "Call the landlord about the radiator", isCheckbox: true),
            NoteLine(text: "Return the library books", isCheckbox: true),
            NoteLine(text: ""),
            NoteLine(text: "Gate 14 — boarding closes 20 min early, so leave by 6."),
        ]
        note.updatedAt = Date().addingTimeInterval(-360)
        return note
    }

    private static func render(note: Note, appearance: NSAppearance?) -> Data? {
        let size = NoteGeometry.defaultSize
        let doc = NoteDocument(note: note, store: nil)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = appearance
        let host = NSHostingView(rootView: NoteView(doc: doc))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = appearance
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle its first layout pass before snapshotting.
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
