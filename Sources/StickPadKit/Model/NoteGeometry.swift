import AppKit

/// macOS lays out in points, and one point is exactly 1/72 inch, so a true
/// 4 x 6 inch sticky note is 288 x 432 points regardless of display scaling.
enum NoteGeometry {
    static let pointsPerInch: CGFloat = 72
    static let inchesWide: CGFloat = 4
    static let inchesTall: CGFloat = 6

    static var defaultSize: NSSize {
        NSSize(width: inchesWide * pointsPerInch, height: inchesTall * pointsPerInch)
    }

    static let minSize = NSSize(width: 200, height: 180)
    private static let cascadeStep: CGFloat = 26

    /// Places a new note just below-right of the note it was created from,
    /// falling back to the top-right of the main screen. Always kept on screen.
    static func frameForNewNote(near anchor: CGRect?) -> CGRect {
        let size = defaultSize
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        var origin: CGPoint
        if let anchor {
            origin = CGPoint(x: anchor.minX + cascadeStep, y: anchor.minY - cascadeStep)
        } else {
            origin = CGPoint(x: visible.maxX - size.width - 40, y: visible.maxY - size.height - 40)
        }

        // Wrap back to the top of the screen once the cascade runs off the bottom.
        if origin.y < visible.minY + 20 || origin.x + size.width > visible.maxX {
            origin = CGPoint(x: visible.maxX - size.width - 40, y: visible.maxY - size.height - 40)
        }
        return clamp(CGRect(origin: origin, size: size), to: visible)
    }

    /// Keeps a stored frame usable if the display setup changed since last launch.
    static func clampToScreens(_ frame: CGRect) -> CGRect {
        let screens = NSScreen.screens
        if screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: 20, dy: 20)) }) {
            return frame
        }
        let visible = (NSScreen.main ?? screens.first)?.visibleFrame ?? frame
        return clamp(frame, to: visible)
    }

    private static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        var f = frame
        f.size.width = min(max(f.width, minSize.width), visible.width)
        f.size.height = min(max(f.height, minSize.height), visible.height)
        f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
        return f
    }
}
