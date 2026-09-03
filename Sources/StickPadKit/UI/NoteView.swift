import SwiftUI
import AppKit

struct NoteView: View {
    @ObservedObject var doc: NoteDocument
    @State private var isHovering = false
    @State private var showingPalette = false

    private var color: NoteColor { doc.note.color }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(color.hairline)
                .frame(height: 1)
            body_
            footer
        }
        .background(color.paper)
        .onHover { isHovering = $0 }
    }

    private func requestDelete() {
        // Confirmed by the app with a native sheet on this panel.
        NotificationCenter.default.post(
            name: .stickPadDeleteNote, object: nil, userInfo: ["id": doc.note.id]
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 2) {
            // Room for the window's close button, which sits over our content.
            Spacer().frame(width: 54)
            Spacer(minLength: 0)

            headerButton("checklist", help: "Toggle checkbox on this line (⌘L)") {
                doc.toggleCheckboxOnFocusedLine()
            }

            headerButton("paintpalette", help: "Note colour") {
                showingPalette.toggle()
            }
            .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
                PalettePicker(selected: doc.note.colorID) { id in
                    doc.setColor(id)
                    showingPalette = false
                }
            }

            headerButton(doc.note.isPinned ? "pin.fill" : "pin.slash",
                         help: doc.note.isPinned ? "Floating above other apps (⌘T)" : "Behaves like a normal window (⌘T)",
                         emphasised: doc.note.isPinned) {
                doc.togglePinned()
            }

            Menu {
                Button("New Note") { NotificationCenter.default.post(name: .stickPadNewNote, object: nil) }
                Divider()
                Menu("Colour") {
                    ForEach(NotePalette.all) { swatch in
                        Button {
                            doc.setColor(swatch.id)
                        } label: {
                            Label(swatch.name,
                                  systemImage: swatch.id == doc.note.colorID ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
                Button("Bigger Text") { doc.setFontSize(doc.note.fontSize + 1) }
                Button("Smaller Text") { doc.setFontSize(doc.note.fontSize - 1) }
                Divider()
                Button("Save Note As…") {
                    NotificationCenter.default.post(name: .stickPadSaveNoteAs, object: nil)
                }
                Divider()
                Button("Clear Completed Items") { doc.clearCompleted() }
                    .disabled(doc.note.checkedCount == 0)
                Button("Reset to 4 × 6 inches") {
                    NotificationCenter.default.post(
                        name: .stickPadResetSize, object: nil, userInfo: ["id": doc.note.id]
                    )
                }
                Divider()
                Button("Delete Note…", role: .destructive) { requestDelete() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .foregroundStyle(color.ink)
            .opacity(controlOpacity)
            .help("More options")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(color.header)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var controlOpacity: Double { isHovering ? 0.75 : 0.35 }

    private func headerButton(_ symbol: String, help: String, emphasised: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(color.ink)
        .opacity(emphasised ? max(controlOpacity, 0.7) : controlOpacity)
        .help(help)
    }

    // MARK: - Lines

    private var body_: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(doc.note.lines) { line in
                    lineRow(line)
                }
                // Clicking the empty space under the last line keeps writing.
                Color.clear
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { doc.focusLastLine() }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .scrollContentBackground(.hidden)
    }

    private func lineRow(_ line: NoteLine) -> some View {
        HStack(alignment: .top, spacing: 7) {
            if line.isCheckbox {
                Button {
                    doc.setChecked(!line.isChecked, on: line.id)
                } label: {
                    Image(systemName: line.isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: doc.note.fontSize, weight: .regular))
                        .foregroundStyle(line.isChecked ? color.ink.opacity(0.5) : color.ink.opacity(0.75))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: lineHeight, alignment: .center)
                .help(line.isChecked ? "Mark as not done" : "Mark as done")
            }

            LineEditor(
                text: doc.binding(forLine: line.id),
                fontSize: doc.note.fontSize,
                inkColor: color.inkNS,
                isStruckThrough: line.isCheckbox && line.isChecked,
                isDimmed: line.isCheckbox && line.isChecked,
                focusTarget: doc.focus?.lineID == line.id ? doc.focus?.caret : nil,
                onFocused: {
                    if doc.focus?.lineID != line.id {
                        doc.focus = FocusTarget(lineID: line.id, caret: .end)
                    }
                },
                onFocusConsumed: {
                    if doc.focus?.lineID == line.id { doc.focus = nil }
                },
                onNewline: { doc.insertLine(after: line.id) },
                onBackspaceAtStart: { doc.backspaceAtStart(of: line.id) },
                onMoveUp: { doc.moveFocus(from: line.id, by: -1) },
                onMoveDown: { doc.moveFocus(from: line.id, by: 1) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lineHeight: CGFloat {
        ceil(NSFont.systemFont(ofSize: doc.note.fontSize).boundingRectForFont.height)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if doc.note.checkboxCount > 0 {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 9))
                Text("\(doc.note.checkedCount)/\(doc.note.checkboxCount)")
                Text("·")
            }
            Text(Self.relative(doc.note.updatedAt))
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(color.faintInk)
                .help("Encrypted on disk with AES-256-GCM")
        }
        .font(.system(size: 10))
        .foregroundStyle(color.faintInk)
        .padding(.horizontal, 14)
        .frame(height: 22)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "edited just now" }
        return "edited " + formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Colour picker

struct PalettePicker: View {
    let selected: String
    let onPick: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note Colour")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(NotePalette.all) { color in
                    Button { onPick(color.id) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color.swatch)
                                .frame(width: 26, height: 26)
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                                .frame(width: 26, height: 26)
                            if color.id == selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.65))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                }
            }
        }
        .padding(14)
    }
}
