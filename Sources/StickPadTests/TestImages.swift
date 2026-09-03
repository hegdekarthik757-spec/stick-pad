import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws throwaway images for the test suite, so nothing depends on files
/// happening to exist on the machine running the tests.
enum TestImages {
    static func png(width: Int, height: Int) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // A gradient rather than a flat fill, so the encoded bytes are
        // distinctive enough for "is this on disk in the clear?" checks.
        for y in stride(from: 0, to: height, by: max(1, height / 16)) {
            ctx.setFillColor(CGColor(srgbRed: CGFloat(y) / CGFloat(max(height, 1)),
                                     green: 0.35, blue: 0.7, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: width, height: max(1, height / 16)))
        }
        let image = ctx.makeImage()!

        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }
}
