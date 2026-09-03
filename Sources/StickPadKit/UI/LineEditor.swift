import AppKit
import SwiftUI

/// An NSTextView subclass used as a single wrapping "row" of a note.
/// It is deliberately built on the TextKit 1 stack so line-fragment geometry is
/// available for caret-aware arrow navigation between rows.
final class LineTextView: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?
    /// Returns true when the paste was consumed as an image.
    var onPasteImage: ((Data) -> Bool)?

    /// Command-V with a picture on the clipboard adds it to the note rather
    /// than pasting nothing (an NSTextView with rich text off drops images).
    override func paste(_ sender: Any?) {
        if let handler = onPasteImage,
           NSPasteboard.general.containsImage,
           let data = NSPasteboard.general.stickPadImageData(),
           handler(data) {
            return
        }
        super.paste(sender)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecomeFirstResponder?() }
        return ok
    }

    /// The caret sits on the first visual line — an up-arrow should leave this row.
    var caretIsOnFirstVisualLine: Bool {
        guard let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 else { return true }
        let glyph = min(lm.glyphIndexForCharacter(at: selectedRange().location), lm.numberOfGlyphs - 1)
        var effective = NSRange()
        let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective, withoutAdditionalLayout: false)
        _ = tc
        return rect.minY < 1
    }

    var caretIsOnLastVisualLine: Bool {
        guard let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 else { return true }
        let glyph = min(lm.glyphIndexForCharacter(at: selectedRange().location), lm.numberOfGlyphs - 1)
        var effective = NSRange()
        let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective, withoutAdditionalLayout: false)
        let used = lm.usedRect(for: tc)
        return rect.maxY >= used.maxY - 1
    }
}

struct LineEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let inkColor: NSColor
    let isStruckThrough: Bool
    let isDimmed: Bool
    /// Non-nil means "take focus now and put the caret here".
    let focusTarget: Caret?

    var onFocused: () -> Void
    var onFocusConsumed: () -> Void
    var onNewline: () -> Void
    var onBackspaceAtStart: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onPasteImage: (Data) -> Bool

    func makeNSView(context: Context) -> LineTextView {
        // Explicit TextKit 1 stack.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let view = LineTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = false
        view.usesFindBar = false
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.onBecomeFirstResponder = { onFocused() }
        view.onPasteImage = { data in onPasteImage(data) }

        context.coordinator.textView = view
        view.string = text
        applyStyle(to: view)
        return view
    }

    func updateNSView(_ view: LineTextView, context: Context) {
        context.coordinator.parent = self
        view.onPasteImage = { [onPasteImage] data in onPasteImage(data) }

        if view.string != text {
            let selected = view.selectedRange()
            view.string = text
            let limit = (text as NSString).length
            view.setSelectedRange(NSRange(location: min(selected.location, limit), length: 0))
        }
        applyStyle(to: view)

        if let focusTarget {
            // Deferred: SwiftUI is mid-update, and changing first responder now
            // would mutate state during view evaluation.
            DispatchQueue.main.async {
                guard let window = view.window else { return }
                if window.firstResponder !== view {
                    window.makeFirstResponder(view)
                }
                let length = (view.string as NSString).length
                let location: Int
                switch focusTarget {
                case .start: location = 0
                case .end: location = length
                case .offset(let o): location = min(max(0, o), length)
                }
                view.setSelectedRange(NSRange(location: location, length: 0))
                view.scrollRangeToVisible(NSRange(location: location, length: 0))
                onFocusConsumed()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LineTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        let proposedWidth = proposal.width ?? 240
        let width = proposedWidth.isFinite ? max(proposedWidth, 40) : 240

        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let minimum = ceil(NSFont.systemFont(ofSize: fontSize).boundingRectForFont.height)
        return CGSize(width: width, height: max(ceil(used), minimum))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Styling

    private func attributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.lineBreakMode = .byWordWrapping

        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: inkColor.withAlphaComponent(isDimmed ? 0.45 : 1.0),
            .paragraphStyle: paragraph
        ]
        if isStruckThrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = inkColor.withAlphaComponent(0.5)
        }
        return attrs
    }

    private func applyStyle(to view: LineTextView) {
        let attrs = attributes()
        view.typingAttributes = attrs
        view.insertionPointColor = inkColor
        if let storage = view.textStorage, storage.length > 0 {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LineEditor
        weak var textView: LineTextView?

        init(_ parent: LineEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let view = textView as? LineTextView else { return false }

            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onNewline()
                return true

            case #selector(NSResponder.deleteBackward(_:)):
                let range = view.selectedRange()
                if range.location == 0 && range.length == 0 {
                    parent.onBackspaceAtStart()
                    return true
                }
                return false

            case #selector(NSResponder.moveUp(_:)):
                if view.caretIsOnFirstVisualLine {
                    parent.onMoveUp()
                    return true
                }
                return false

            case #selector(NSResponder.moveDown(_:)):
                if view.caretIsOnLastVisualLine {
                    parent.onMoveDown()
                    return true
                }
                return false

            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                // Tab shouldn't escape the note into the window's focus ring.
                return true

            default:
                return false
            }
        }
    }
}
