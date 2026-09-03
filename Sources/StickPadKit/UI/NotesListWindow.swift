import SwiftUI
import AppKit

struct NotesListView: View {
    @ObservedObject var store: NoteStore
    @State private var query = ""

    private var results: [Note] {
        let sorted = store.notes.sorted { $0.updatedAt > $1.updatedAt }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { note in
            note.lines.contains { $0.text.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = store.loadError {
                lockedState(error)
            } else if results.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(results) { note in
                        row(note)
                            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .stickPadNewNote, object: nil)
            } label: {
                Label("New Note", systemImage: "plus")
            }
            .disabled(store.isReadOnly)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("Search notes", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
    }

    private func row(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(note.color.swatch)
                .frame(width: 12, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if note.checkboxCount > 0 {
                        Text("\(note.checkedCount)/\(note.checkboxCount) done")
                    }
                    if !note.preview.isEmpty {
                        Text(note.preview).lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(note.updatedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    if note.isOpen {
                        Image(systemName: "macwindow")
                            .foregroundStyle(.tertiary)
                            .help("Currently on screen")
                    }
                    Button {
                        NotificationCenter.default.post(
                            name: .stickPadDeleteNote, object: nil, userInfo: ["id": note.id]
                        )
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete note")
                }
                .font(.system(size: 11))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            NotificationCenter.default.post(
                name: .stickPadOpenNote, object: nil, userInfo: ["id": note.id]
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No notes yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
            if query.isEmpty {
                Text("Press ⌘N to write your first note.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lockedState(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Your notes are locked")
                .font(.system(size: 13, weight: .semibold))
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text("Saving is paused so nothing is overwritten. Use Note ▸ Import Encryption Key… to restore the matching key.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

@MainActor
final class NotesListWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow

    init(store: NoteStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "All Notes"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("StickPadNotesList")
        window.contentView = NSHostingView(rootView: NotesListView(store: store))
        window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
