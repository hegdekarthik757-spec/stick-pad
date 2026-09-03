import AppKit

/// The "Format:" popup shown inside the Save panel.
@MainActor
final class SaveFormatAccessory: NSView {
    private let popup = NSPopUpButton(frame: NSRect(x: 76, y: 13, width: 200, height: 25), pullsDown: false)
    var onChange: ((ExportFormat) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 52))

        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 4, y: 17, width: 64, height: 18)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        addSubview(label)

        popup.addItems(withTitles: ExportFormat.allCases.map(\.displayName))
        popup.target = self
        popup.action = #selector(selectionChanged)
        addSubview(popup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var format: ExportFormat {
        let index = popup.indexOfSelectedItem
        return ExportFormat.allCases.indices.contains(index) ? ExportFormat.allCases[index] : .markdown
    }

    @objc private func selectionChanged() { onChange?(format) }
}
