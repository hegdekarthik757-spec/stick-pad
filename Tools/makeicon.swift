// Draws the Stick Pad app icon at every size the iconset needs.
// Uses a plain bitmap CGContext so it runs headless, without a window server.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(pixels: Int) -> CGImage? {
    let s = CGFloat(pixels) / 1024.0
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: s, y: s)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let card = CGRect(x: 112, y: 112, width: 800, height: 800)
    let radius: CGFloat = 180

    // Drop shadow under the card.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: rgb(0x000000, 0.28))
    ctx.setFillColor(rgb(0xF7D267))
    ctx.addPath(roundedRect(card, radius))
    ctx.fillPath()
    ctx.restoreGState()

    // Paper gradient.
    ctx.saveGState()
    ctx.addPath(roundedRect(card, radius))
    ctx.clip()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [rgb(0xFFEFB4), rgb(0xF6C94F)] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: card.maxY),
                               end: CGPoint(x: 0, y: card.minY),
                               options: [])
    }
    // Warm highlight along the top edge.
    ctx.setFillColor(rgb(0xFFFFFF, 0.30))
    ctx.fill(CGRect(x: card.minX, y: card.maxY - 120, width: card.width, height: 120))
    ctx.restoreGState()

    let ink = 0x3B2E10 as UInt32

    // Checklist rows: one done, two to go.
    struct Row { let y: CGFloat; let width: CGFloat; let done: Bool }
    let rows = [
        Row(y: 640, width: 386, done: true),
        Row(y: 472, width: 330, done: false),
        Row(y: 304, width: 386, done: false)
    ]

    for row in rows {
        let box = CGRect(x: 206, y: row.y - 54, width: 108, height: 108)
        let boxPath = roundedRect(box, 30)

        if row.done {
            ctx.setFillColor(rgb(ink, 0.86))
            ctx.addPath(boxPath)
            ctx.fillPath()
            // Tick
            ctx.setStrokeColor(rgb(0xFFF3CE))
            ctx.setLineWidth(18)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: box.minX + 26, y: box.midY + 2))
            ctx.addLine(to: CGPoint(x: box.midX - 4, y: box.minY + 28))
            ctx.addLine(to: CGPoint(x: box.maxX - 22, y: box.maxY - 30))
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(rgb(ink, 0.55))
            ctx.setLineWidth(22)
            ctx.addPath(boxPath)
            ctx.strokePath()
        }

        // Text line beside the box.
        let lineRect = CGRect(x: 360, y: row.y - 26, width: row.width, height: 52)
        ctx.setFillColor(rgb(ink, row.done ? 0.30 : 0.48))
        ctx.addPath(roundedRect(lineRect, 26))
        ctx.fillPath()

    }

    // Inner edge so the card reads as paper, not a flat swatch.
    ctx.setStrokeColor(rgb(0x000000, 0.10))
    ctx.setLineWidth(6)
    ctx.addPath(roundedRect(card.insetBy(dx: 3, dy: 3), radius - 3))
    ctx.strokePath()

    return ctx.makeImage()
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, size) in variants {
    guard let image = drawIcon(pixels: size) else {
        FileHandle.standardError.write("failed to draw \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("wrote \(variants.count) icon sizes to \(outDir)")
