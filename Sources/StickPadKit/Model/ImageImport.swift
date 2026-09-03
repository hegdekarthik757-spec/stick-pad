import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever the user dropped, pasted or picked into something worth
/// storing: right way up, not absurdly large, and in a sensible format.
enum ImageImport {
    /// Photos straight from a camera are far larger than a 4 x 6 inch note can
    /// ever show, and every pixel would be encrypted and written to disk.
    static let maxPixelDimension: CGFloat = 2048

    struct Result {
        let data: Data
        let pixelSize: CGSize
    }

    static func normalize(data: Data) -> Result? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return normalize(source: source)
    }

    static func normalize(contentsOf url: URL) -> Result? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return normalize(source: source)
    }

    private static func normalize(source: CGImageSource) -> Result? {
        // `createThumbnail` applies the EXIF orientation and downsamples in one
        // step, so a sideways phone photo comes out upright.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }

        // Screenshots and logos keep their transparency as PNG; photographs
        // compress far better as JPEG.
        let type: UTType = hasAlpha ? .png : .jpeg
        let properties: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.9]

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return Result(data: output as Data,
                      pixelSize: CGSize(width: image.width, height: image.height))
    }

    /// File types the "Add Image…" panel and drop handler accept.
    static var acceptedTypes: [UTType] { [.image] }
}

extension NSPasteboard {
    /// Image bytes on the pasteboard, whether copied from an app or as a file.
    func stickPadImageData() -> Data? {
        if let url = (readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL])?.first, let data = try? Data(contentsOf: url) {
            return data
        }
        for type in [NSPasteboard.PasteboardType.png,
                     NSPasteboard.PasteboardType.tiff] {
            if let data = data(forType: type) { return data }
        }
        return nil
    }

    var containsImage: Bool {
        canReadObject(forClasses: [NSImage.self], options: nil)
    }
}
