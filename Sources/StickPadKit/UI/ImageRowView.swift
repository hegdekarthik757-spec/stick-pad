import SwiftUI
import AppKit

/// Decoded images, kept in memory so scrolling a note doesn't decrypt and
/// decode the same picture over and over. Entries are dropped when the note
/// window closes.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var images: [UUID: NSImage] = [:]

    func image(for id: UUID, loader: () -> Data?) -> NSImage? {
        if let cached = images[id] { return cached }
        guard let data = loader(), let image = NSImage(data: data) else { return nil }
        images[id] = image
        return image
    }

    /// Puts an image in without a disk round trip. Used by the preview
    /// renderer, which has no store to decrypt from.
    func preload(_ image: NSImage, for id: UUID) { images[id] = image }

    func forget(_ id: UUID) { images.removeValue(forKey: id) }
    func forget(_ ids: [UUID]) { ids.forEach { images.removeValue(forKey: $0) } }
}

struct ImageRowView: View {
    @ObservedObject var doc: NoteDocument
    let line: NoteLine
    let color: NoteColor
    /// Width available inside the note's padding.
    let availableWidth: CGFloat

    @State private var isHovering = false

    /// An image is scaled to the note's width but capped in height, so a tall
    /// picture can't push everything else out of a 4 x 6 inch note.
    private static let maxHeight: CGFloat = 260

    private var displaySize: CGSize {
        let pixels = line.imagePixelSize
        let width = max(availableWidth, 40)
        let scaled = width * (pixels.height / pixels.width)
        if scaled <= Self.maxHeight {
            return CGSize(width: width, height: scaled)
        }
        return CGSize(width: Self.maxHeight * (pixels.width / pixels.height), height: Self.maxHeight)
    }

    var body: some View {
        let size = displaySize
        ZStack(alignment: .topTrailing) {
            Group {
                if let id = line.imageID,
                   let image = ImageCache.shared.image(for: id, loader: { doc.imageData(for: id) }) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    missingImage
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(color.ink.opacity(0.15), lineWidth: 1)
            )

            if isHovering {
                Button {
                    if let id = line.imageID { ImageCache.shared.forget(id) }
                    doc.removeImage(line.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help("Remove this image")
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topTrailing)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var missingImage: some View {
        ZStack {
            color.ink.opacity(0.06)
            VStack(spacing: 4) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 18))
                Text("Image unavailable")
                    .font(.system(size: 10))
            }
            .foregroundStyle(color.faintInk)
        }
    }
}
