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

    /// A stand-in picture so the image row can be seen in the preview.
    private static func sampleImage() -> NSImage {
        let size = NSSize(width: 400, height: 240)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.55, blue: 0.85, alpha: 1),
                            NSColor(srgbRed: 0.86, green: 0.62, blue: 0.45, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 55)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 300, y: 160, width: 54, height: 54)).fill()
        NSColor(srgbRed: 0.18, green: 0.34, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: -40, y: -90, width: 260, height: 190)).fill()
        NSBezierPath(ovalIn: NSRect(x: 150, y: -110, width: 300, height: 200)).fill()
        image.unlockFocus()
        return image
    }

    private static func sampleNote(colorID: String) -> Note {
        let imageID = UUID()
        ImageCache.shared.preload(sampleImage(), for: imageID)
        var note = Note()
        note.colorID = colorID
        note.lines = [
            NoteLine(text: "Weekend"),
            NoteLine(text: "Book the ferry tickets before Friday", isCheckbox: true, isChecked: true),
            NoteLine(text: "Pick up the dry cleaning", isCheckbox: true, isChecked: true),
            NoteLine(text: "Call the landlord about the radiator", isCheckbox: true),
            NoteLine(text: ""),
            NoteLine(imageID: imageID, pixelSize: CGSize(width: 400, height: 240)),
            NoteLine(text: "Gate 14 — boarding closes 20 min early."),
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
