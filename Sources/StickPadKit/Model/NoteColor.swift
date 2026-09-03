import AppKit
import SwiftUI

/// A note colour is defined as a light/dark pair so notes stay legible in both
/// system appearances. Colours are resolved through NSColor's dynamic provider.
struct NoteColor: Identifiable, Hashable {
    let id: String
    let name: String
    private let paperLight: UInt32
    private let paperDark: UInt32
    private let inkLight: UInt32
    private let inkDark: UInt32

    init(id: String, name: String, paperLight: UInt32, paperDark: UInt32,
         inkLight: UInt32 = 0x1F1B12, inkDark: UInt32 = 0xF2EEE4) {
        self.id = id
        self.name = name
        self.paperLight = paperLight
        self.paperDark = paperDark
        self.inkLight = inkLight
        self.inkDark = inkDark
    }

    var paperNS: NSColor { NoteColor.dynamic(light: paperLight, dark: paperDark) }
    var inkNS: NSColor { NoteColor.dynamic(light: inkLight, dark: inkDark) }

    var paper: Color { Color(nsColor: paperNS) }
    var ink: Color { Color(nsColor: inkNS) }

    /// A shade off the paper, used for the header strip. Derived inside the
    /// dynamic provider so the blend happens against the *resolved* paper —
    /// blending a dynamic NSColor outside a drawing context picks whichever
    /// appearance happens to be current, which is not necessarily the note's.
    var headerNS: NSColor {
        NoteColor.dynamic(light: paperLight, dark: paperDark) { base, isDark in
            base.blended(withFraction: 0.11, of: isDark ? .white : .black) ?? base
        }
    }
    var header: Color { Color(nsColor: headerNS) }
    var hairline: Color { ink.opacity(0.12) }
    var faintInk: Color { ink.opacity(0.45) }

    /// Swatch shown in the palette picker (always the light tone, so the
    /// palette reads as the same set of colours in either appearance).
    var swatch: Color { Color(nsColor: NoteColor.solid(paperLight)) }

    private static func solid(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0)
    }

    private static func dynamic(light: UInt32, dark: UInt32,
                                transform: ((NSColor, Bool) -> NSColor)? = nil) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let base = solid(isDark ? dark : light)
            return transform?(base, isDark) ?? base
        }
    }
}

enum NotePalette {
    static let defaultColorID = "butter"

    static let all: [NoteColor] = [
        NoteColor(id: "butter", name: "Butter", paperLight: 0xFFE9A3, paperDark: 0x4A3F1C),
        NoteColor(id: "peach",  name: "Peach",  paperLight: 0xFFD3B0, paperDark: 0x4C3324),
        NoteColor(id: "rose",   name: "Rose",   paperLight: 0xFFC2CE, paperDark: 0x4E2530),
        NoteColor(id: "lilac",  name: "Lilac",  paperLight: 0xDCC8FF, paperDark: 0x372A52),
        NoteColor(id: "sky",    name: "Sky",    paperLight: 0xBEE0FF, paperDark: 0x1E3A50),
        NoteColor(id: "mint",   name: "Mint",   paperLight: 0xBDF0D2, paperDark: 0x1E4434),
        NoteColor(id: "lime",   name: "Lime",   paperLight: 0xE0F2A8, paperDark: 0x3A4520),
        NoteColor(id: "sand",   name: "Sand",   paperLight: 0xEADDC7, paperDark: 0x3E362A),
        NoteColor(id: "slate",  name: "Slate",  paperLight: 0xD5DAE0, paperDark: 0x2B3138),
        NoteColor(id: "paper",  name: "Paper",  paperLight: 0xFBF7EF, paperDark: 0x24242A)
    ]

    static func color(id: String) -> NoteColor {
        all.first { $0.id == id } ?? all[0]
    }

    static func next(after id: String) -> String {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return defaultColorID }
        return all[(i + 1) % all.count].id
    }
}
