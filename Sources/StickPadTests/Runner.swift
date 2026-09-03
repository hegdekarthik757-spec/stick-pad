import Foundation
import AppKit
import CryptoKit
@testable import StickPadKit

@main
@MainActor
struct Runner {
    static func main() {
        print("Stick Pad — test suite")

        cryptoSuite()
        storeSuite()
        editingSuite()
        exportSuite()
        imageSuite()
        windowSuite()
        menuSuite()

        exit(T.report())
    }

    // MARK: - Saving to files

    static func exportSuite() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickpad-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func note(_ lines: [NoteLine]) -> Note {
            var n = Note()
            n.lines = lines
            return n
        }

        T.suite("Saving a note to a file") {
            T.test("Markdown keeps checklists as task lists") {
                let n = note([NoteLine(text: "Weekend"),
                              NoteLine(text: "ferry", isCheckbox: true, isChecked: true),
                              NoteLine(text: "laundry", isCheckbox: true)])
                let text = NoteExporter.text(for: n, format: .markdown)
                T.equal(text, "Weekend\n- [x] ferry\n- [ ] laundry\n", "task-list syntax")
            }

            T.test("plain text uses simple brackets") {
                let n = note([NoteLine(text: "ferry", isCheckbox: true, isChecked: true),
                              NoteLine(text: "laundry", isCheckbox: true)])
                let text = NoteExporter.text(for: n, format: .plainText)
                T.equal(text, "[x] ferry\n[ ] laundry\n", "bracket syntax")
            }

            T.test("blank lines are preserved") {
                let n = note([NoteLine(text: "one"), NoteLine(text: ""), NoteLine(text: "two")])
                T.equal(NoteExporter.text(for: n, format: .markdown), "one\n\ntwo\n", "the gap survives")
            }

            T.test("filenames are legal, visible and bounded") {
                T.equal(NoteExporter.filename(for: note([NoteLine(text: "Trip / Notes: 2026")])),
                        "Trip Notes 2026", "slashes and colons are removed")
                T.equal(NoteExporter.filename(for: note([NoteLine(text: ".hidden")])),
                        "hidden", "a leading dot would hide the file")
                T.equal(NoteExporter.filename(for: note([NoteLine(text: "   ")])),
                        "New note", "a blank note still gets a name")
                let long = NoteExporter.filename(for: note([NoteLine(text: String(repeating: "a", count: 200))]))
                T.expect(long.count <= 60, "long titles are trimmed")
            }

            T.test("writes a file that reads back byte for byte") {
                let n = note([NoteLine(text: "buy stamps", isCheckbox: true)])
                let url = root.appendingPathComponent("single.md")
                try NoteExporter.data(for: n, format: .markdown).write(to: url)
                let read = try String(contentsOf: url, encoding: .utf8)
                T.equal(read, "- [ ] buy stamps\n", "round trips through the disk")
            }
        }

        T.suite("Saving every note") {
            T.test("writes one file per note into a new folder") {
                let dir = root.appendingPathComponent("all")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let notes = [note([NoteLine(text: "Groceries")]),
                             note([NoteLine(text: "Reading list")]),
                             note([NoteLine(text: "Groceries")])]

                let result = try NoteExporter.exportAll(notes, into: dir)
                T.equal(result.count, 3, "every note is written")

                let files = try FileManager.default.contentsOfDirectory(atPath: result.folder.path).sorted()
                T.equal(files, ["Groceries 2.md", "Groceries.md", "Reading list.md"],
                        "duplicate titles get distinct filenames")
            }

            T.test("never writes into an existing folder") {
                let dir = root.appendingPathComponent("twice")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let first = try NoteExporter.exportAll([note([NoteLine(text: "A")])], into: dir)
                let second = try NoteExporter.exportAll([note([NoteLine(text: "A")])], into: dir)
                T.notEqual(first.folder, second.folder, "a second export gets its own folder")
                T.expect(second.folder.lastPathComponent == "Stick Pad Notes 2", "and an obvious name")
            }

            T.test("refuses to export nothing") {
                T.throwsError("an empty export is an error, not an empty folder") {
                    _ = try NoteExporter.exportAll([], into: root)
                }
            }
        }

        T.suite("Encrypted backup") {
            T.test("carries notes and images in one sealed file") {
                let key = SymmetricKey(size: .bits256)
                let png = TestImages.png(width: 40, height: 30)
                let imageID = UUID()

                var n = Note()
                n.lines = [NoteLine(text: "with a picture"),
                           NoteLine(imageID: imageID, pixelSize: CGSize(width: 40, height: 30))]

                let archive = try BackupArchive.make(notes: [n], images: [imageID: png], key: key)
                let restored = try BackupArchive.read(archive, key: key)

                T.equal(restored.notes.count, 1, "the note comes back")
                T.equal(restored.notes[0].lines[1].imageID, imageID, "the image row still points at its file")
                T.equal(restored.images[imageID], png, "and the picture itself is inside the backup")
            }

            T.test("a backup is opaque and needs the right key") {
                let key = SymmetricKey(size: .bits256)
                let png = TestImages.png(width: 8, height: 8)
                var n = Note()
                n.lines = [NoteLine(text: "wifi password hunter2")]
                let archive = try BackupArchive.make(notes: [n], images: [UUID(): png], key: key)

                T.expect(archive.range(of: Data("hunter2".utf8)) == nil, "no readable note text")
                T.expect(archive.range(of: png) == nil, "no raw image bytes either")
                T.throwsError("another key cannot open it") {
                    _ = try BackupArchive.read(archive, key: SymmetricKey(size: .bits256))
                }
            }

            T.test("still opens backups written before images existed") {
                let key = SymmetricKey(size: .bits256)
                var payload = StorePayload()
                var n = Note()
                n.lines = [NoteLine(text: "an old note")]
                payload.notes = [n]

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let legacy = try CryptoBox.seal(try encoder.encode(payload), key: key)

                let restored = try BackupArchive.read(legacy, key: key)
                T.equal(restored.notes.count, 1, "the old notes load")
                T.equal(restored.notes[0].lines[0].text, "an old note", "with their text intact")
                T.expect(restored.images.isEmpty, "and no images, as expected")
            }

            T.test("backup filenames are dated") {
                var components = DateComponents()
                components.year = 2026; components.month = 9; components.day = 1
                let date = Calendar(identifier: .gregorian).date(from: components)!
                T.equal(NoteExporter.backupFilename(date: date), "Stick Pad Backup 2026-09-01.spad", "dated name")
            }
        }
    }

    // MARK: - Images

    static func imageSuite() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickpad-images-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        T.suite("Importing an image") {
            T.test("keeps a small image at its own size") {
                let png = TestImages.png(width: 120, height: 80)
                guard let result = ImageImport.normalize(data: png) else {
                    T.expect(false, "a valid PNG imports")
                    return
                }
                T.equal(result.pixelSize, CGSize(width: 120, height: 80), "size is unchanged")
            }

            T.test("downsamples anything larger than the cap") {
                let png = TestImages.png(width: 4000, height: 2000)
                guard let result = ImageImport.normalize(data: png) else {
                    T.expect(false, "a large PNG imports")
                    return
                }
                T.equal(result.pixelSize.width, ImageImport.maxPixelDimension, "long edge is capped")
                T.equal(result.pixelSize.height, ImageImport.maxPixelDimension / 2, "aspect ratio is kept")
                T.expect(result.data.count < png.count, "and the stored bytes shrink")
            }

            T.test("rejects things that are not images") {
                T.expect(ImageImport.normalize(data: Data("this is just text".utf8)) == nil,
                         "text is not accepted as a picture")
                T.expect(ImageImport.normalize(data: Data()) == nil, "nor is nothing")
            }
        }

        T.suite("Image storage") {
            T.test("images are encrypted on disk, one file each") {
                let key = SymmetricKey(size: .bits256)
                let store = AttachmentStore(key: key, directory: root.appendingPathComponent("sealed"))
                let png = TestImages.png(width: 64, height: 64)
                let id = UUID()

                try store.write(png, id: id)
                let onDisk = try Data(contentsOf: store.url(for: id))
                T.expect(onDisk.range(of: png) == nil, "the raw picture is not on disk")
                T.equal(Array(onDisk.prefix(4)), Array("SPAD".utf8), "it is a sealed Stick Pad file")
                T.equal(try store.read(id: id), png, "and it decrypts back to the original")
            }

            T.test("an image file is owner-readable only") {
                let store = AttachmentStore(key: SymmetricKey(size: .bits256),
                                            directory: root.appendingPathComponent("perms"))
                let id = UUID()
                try store.write(TestImages.png(width: 8, height: 8), id: id)
                let attrs = try FileManager.default.attributesOfItem(atPath: store.url(for: id).path)
                T.equal((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600, "file mode is 600")
            }

            T.test("another key cannot read an image") {
                let directory = root.appendingPathComponent("wrongkey")
                let mine = AttachmentStore(key: SymmetricKey(size: .bits256), directory: directory)
                let theirs = AttachmentStore(key: SymmetricKey(size: .bits256), directory: directory)
                let id = UUID()
                try mine.write(TestImages.png(width: 8, height: 8), id: id)
                T.throwsError("a foreign key is refused") { _ = try theirs.read(id: id) }
            }

            T.test("unreferenced images are cleaned up, referenced ones kept") {
                let store = AttachmentStore(key: SymmetricKey(size: .bits256),
                                            directory: root.appendingPathComponent("prune"))
                let keep = UUID(), drop = UUID()
                try store.write(TestImages.png(width: 8, height: 8), id: keep)
                try store.write(TestImages.png(width: 8, height: 8), id: drop)

                let removed = store.pruneOrphans(keeping: [keep])
                T.equal(removed, 1, "one orphan removed")
                T.expect(store.exists(id: keep), "the referenced image survives")
                T.expect(!store.exists(id: drop), "the orphan is gone")
            }
        }

        T.suite("Image rows in a note") {
            T.test("notes written before images existed still decode") {
                let legacy = Data("""
                {"id":"7B0E7C3E-5B1E-4E0E-9B7E-9C2F1A3D4E5F","text":"hello",\
                "isCheckbox":true,"isChecked":false}
                """.utf8)
                guard let line = try? JSONDecoder().decode(NoteLine.self, from: legacy) else {
                    T.expect(false, "an old note line decodes")
                    return
                }
                T.equal(line.text, "hello", "text survives")
                T.expect(line.isCheckbox, "checkbox survives")
                T.expect(!line.isImage, "and it is not an image")
                T.expect(line.imageID == nil, "with no attachment")
            }

            T.test("an image row reports its size and identity") {
                let id = UUID()
                let line = NoteLine(imageID: id, pixelSize: CGSize(width: 300, height: 150))
                T.expect(line.isImage, "it is an image row")
                T.equal(line.imagePixelSize, CGSize(width: 300, height: 150), "size round trips")
            }

            T.test("a damaged image row still lays out") {
                var line = NoteLine(imageID: UUID(), pixelSize: CGSize(width: 100, height: 50))
                line.imageWidth = 0
                T.equal(line.imagePixelSize, CGSize(width: 1, height: 1), "falls back to a square")
            }

            T.test("a note of only images is still named and not empty") {
                var n = Note()
                n.lines = [NoteLine(imageID: UUID(), pixelSize: CGSize(width: 10, height: 10))]
                T.equal(n.title, "Image note", "it gets a sensible title")
                T.expect(!n.isEffectivelyEmpty, "and does not count as blank")
                T.equal(n.imageIDs.count, 1, "its attachment is listed")
            }
        }

        T.suite("Saving notes that contain images") {
            T.test("Markdown links the picture, plain text notes it") {
                let id = UUID()
                var n = Note()
                n.lines = [NoteLine(text: "Holiday"),
                           NoteLine(imageID: id, pixelSize: CGSize(width: 10, height: 10))]

                let md = NoteExporter.text(for: n, format: .markdown, imagePath: { _ in "Holiday images/a.png" })
                T.equal(md, "Holiday\n![image](Holiday%20images/a.png)\n", "spaces are escaped in the link")

                let txt = NoteExporter.text(for: n, format: .plainText, imagePath: { _ in "a.png" })
                T.equal(txt, "Holiday\n[image: a.png]\n", "plain text names the file")

                let orphan = NoteExporter.text(for: n, format: .markdown)
                T.equal(orphan, "Holiday\n*(image)*\n", "a missing picture is still marked")
            }

            T.test("writing a note puts its images in a folder beside it") {
                let id = UUID()
                let png = TestImages.png(width: 20, height: 20)
                var n = Note()
                n.lines = [NoteLine(text: "Trip"),
                           NoteLine(imageID: id, pixelSize: CGSize(width: 20, height: 20))]

                let dir = root.appendingPathComponent("single")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent("Trip.md")
                try NoteExporter.write(note: n, to: file, format: .markdown, imageData: { $0 == id ? png : nil })

                let imageFile = dir.appendingPathComponent("Trip images")
                    .appendingPathComponent("\(id.uuidString.lowercased()).png")
                T.expect(FileManager.default.fileExists(atPath: imageFile.path), "the picture is written out")
                T.equal(try Data(contentsOf: imageFile), png, "unchanged")

                let text = try String(contentsOf: file, encoding: .utf8)
                T.expect(text.contains("Trip%20images/"), "and the note links to it")
            }

            T.test("a folder export shares one images directory") {
                let id = UUID()
                let png = TestImages.png(width: 12, height: 12)
                var a = Note(); a.lines = [NoteLine(text: "One"),
                                           NoteLine(imageID: id, pixelSize: CGSize(width: 12, height: 12))]
                var b = Note(); b.lines = [NoteLine(text: "Two"),
                                           NoteLine(imageID: id, pixelSize: CGSize(width: 12, height: 12))]

                let dir = root.appendingPathComponent("folder")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let result = try NoteExporter.exportAll([a, b], into: dir, imageData: { $0 == id ? png : nil })

                let images = try FileManager.default.contentsOfDirectory(
                    atPath: result.folder.appendingPathComponent("images").path)
                T.equal(images.count, 1, "a shared image is written once, not twice")

                let text = try String(contentsOf: result.folder.appendingPathComponent("One.md"), encoding: .utf8)
                T.expect(text.contains("images/"), "notes link into the shared folder")
            }

            T.test("names image files by their real format") {
                let png = TestImages.png(width: 4, height: 4)
                T.equal(NoteExporter.fileExtension(forImage: png), "png", "PNG is detected by signature")
                T.equal(NoteExporter.fileExtension(forImage: Data([0xFF, 0xD8, 0xFF])), "jpg", "otherwise JPEG")
            }
        }
    }

    // MARK: - Menus

    /// Menu items are dispatched by selector through the responder chain, so a
    /// renamed method leaves a permanently greyed-out item rather than a build
    /// error. This walks the real menu and checks every action can be handled.
    static func menuSuite() {
        _ = NSApplication.shared
        MainMenu.install()

        T.suite("Menus") {
            // Selectors handled by the focused text view, not the app.
            let responderProvided: Set<String> = [
                "undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:", "performMiniaturize:"
            ]

            func items(of menu: NSMenu) -> [NSMenuItem] {
                menu.items.flatMap { item -> [NSMenuItem] in
                    if let submenu = item.submenu { return items(of: submenu) }
                    return [item]
                }
            }

            T.test("every menu item points at an action something can handle") {
                let delegate = AppDelegate()
                guard let main = NSApp.mainMenu else {
                    T.expect(false, "the main menu was installed")
                    return
                }
                let unhandled = items(of: main).filter { item in
                    guard let action = item.action else { return false }
                    let name = NSStringFromSelector(action)
                    return !(delegate.responds(to: action)
                             || NSApp.responds(to: action)
                             || responderProvided.contains(name))
                }
                T.equal(unhandled.map(\.title), [], "no menu item is wired to a missing method")
            }

            T.test("the saving commands are present with their shortcuts") {
                guard let main = NSApp.mainMenu else { return }
                let all = items(of: main)
                func item(_ title: String) -> NSMenuItem? { all.first { $0.title == title } }

                T.expect(item("Save Note As…") != nil, "Save Note As is in the menus")
                T.equal(item("Save Note As…")?.keyEquivalent, "s", "bound to Command-S")

                let saveAll = item("Save All Notes to a Folder…")
                T.expect(saveAll != nil, "Save All Notes is in the menus")
                T.equal(saveAll?.keyEquivalentModifierMask, [.command, .shift], "bound to Shift-Command-S")

                T.expect(item("Save Encrypted Backup…") != nil, "the encrypted backup command exists")
                T.expect(item("Restore from Encrypted Backup…") != nil, "and its restore counterpart")
            }

            T.test("editing commands are available to the note editor") {
                guard let main = NSApp.mainMenu else { return }
                let titles = Set(items(of: main).map(\.title))
                for expected in ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All"] {
                    T.expect(titles.contains(expected), "\(expected) is available while typing")
                }
            }
        }
    }

    // MARK: - Window behaviour

    /// These build real panels (without showing them) so the "stays on top"
    /// requirement is checked against AppKit rather than assumed.
    static func windowSuite() {
        _ = NSApplication.shared

        T.suite("Note windows") {
            T.test("opens at 4 x 6 inches and floats above other apps") {
                let controller = NotePanelController(note: Note(), store: nil)
                T.equal(controller.panel.frame.size, NoteGeometry.defaultSize, "4 x 6 inches on screen")
                T.equal(controller.panel.level, .floating, "floating level keeps it above other apps")
            }

            T.test("can take keyboard focus without activating the app") {
                let controller = NotePanelController(note: Note(), store: nil)
                T.expect(controller.panel.canBecomeKey, "you can type into a note that is not the front app")
                T.expect(!controller.panel.canBecomeMain, "but it never becomes the main window")
                T.expect(controller.panel.styleMask.contains(.nonactivatingPanel),
                         "clicking a note does not pull the whole app forward")
                T.expect(!controller.panel.hidesOnDeactivate,
                         "notes stay put when you switch apps")
            }

            T.test("follows you between Spaces and full-screen apps") {
                let controller = NotePanelController(note: Note(), store: nil)
                T.expect(controller.panel.collectionBehavior.contains(.canJoinAllSpaces),
                         "visible on every Space")
                T.expect(controller.panel.collectionBehavior.contains(.fullScreenAuxiliary),
                         "visible over full-screen apps")
            }

            T.test("unpinning drops the note to the normal window level") {
                var note = Note()
                note.isPinned = false
                let controller = NotePanelController(note: note, store: nil)
                T.equal(controller.panel.level, .normal, "an unpinned note behaves like any window")

                controller.doc.togglePinned()
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                T.equal(controller.panel.level, .floating, "pinning it again brings it back on top")
            }

            T.test("is closable and resizable, but not minimizable") {
                let controller = NotePanelController(note: Note(), store: nil)
                T.expect(controller.panel.styleMask.contains(.closable), "the note can be closed")
                T.expect(controller.panel.styleMask.contains(.resizable), "the note can be resized")
                T.expect(controller.panel.standardWindowButton(.miniaturizeButton)?.isHidden == true,
                         "a floating note has no reason to minimize")
            }

            T.test("reopens where it was left") {
                var note = Note()
                let frame = CGRect(x: 120, y: 140, width: 320, height: 500)
                note.frame = frame
                let controller = NotePanelController(note: note, store: nil)
                T.equal(controller.panel.frame, frame, "the stored frame is restored")
            }

            T.test("resetting size returns the note to 4 x 6 inches") {
                var note = Note()
                note.frame = CGRect(x: 200, y: 200, width: 600, height: 300)
                let controller = NotePanelController(note: note, store: nil)
                controller.resetToStandardSize()
                T.equal(controller.panel.frame.size, NoteGeometry.defaultSize, "back to 4 x 6")
            }
        }
    }

    // MARK: - Encryption

    static func cryptoSuite() {
        T.suite("Encryption") {
            T.test("seals and opens a round trip") {
                let key = SymmetricKey(size: .bits256)
                let plaintext = Data("shopping list: oat milk, batteries".utf8)
                let sealed = try CryptoBox.seal(plaintext, key: key)
                T.equal(try CryptoBox.open(sealed, key: key), plaintext, "round trip")
            }

            T.test("uses a fresh nonce for every write") {
                let key = SymmetricKey(size: .bits256)
                let plaintext = Data("same input".utf8)
                let a = try CryptoBox.seal(plaintext, key: key)
                let b = try CryptoBox.seal(plaintext, key: key)
                T.notEqual(a, b, "identical plaintext must not produce identical ciphertext")
            }

            T.test("rejects the wrong key") {
                let sealed = try CryptoBox.seal(Data("secret".utf8), key: SymmetricKey(size: .bits256))
                T.throwsError("a different key must not decrypt") {
                    _ = try CryptoBox.open(sealed, key: SymmetricKey(size: .bits256))
                }
            }

            T.test("rejects tampered ciphertext") {
                let key = SymmetricKey(size: .bits256)
                var sealed = try CryptoBox.seal(Data("transfer 10 pounds".utf8), key: key)
                sealed[sealed.count - 12] ^= 0x01
                T.throwsError("a flipped bit must fail authentication") {
                    _ = try CryptoBox.open(sealed, key: key)
                }
            }

            T.test("rejects a tampered header") {
                let key = SymmetricKey(size: .bits256)
                var sealed = try CryptoBox.seal(Data("hello".utf8), key: key)
                sealed[4] = 9
                T.throwsError("the version byte is authenticated") {
                    _ = try CryptoBox.open(sealed, key: key)
                }
            }

            T.test("rejects foreign and empty data") {
                let key = SymmetricKey(size: .bits256)
                T.throwsError("not a Stick Pad file") {
                    _ = try CryptoBox.open(Data("not a stick pad file".utf8), key: key)
                }
                T.throwsError("empty data") { _ = try CryptoBox.open(Data(), key: key) }
            }

            T.test("round-trips an exported key") {
                let key = SymmetricKey(size: .bits256)
                let base64 = key.withUnsafeBytes { Data($0) }.base64EncodedString()
                let restored = SymmetricKey(data: Data(base64Encoded: base64)!)
                let sealed = try CryptoBox.seal(Data("notes".utf8), key: key)
                T.equal(try CryptoBox.open(sealed, key: restored), Data("notes".utf8),
                        "an exported key must open the same store")
            }
        }
    }

    // MARK: - Encrypted store

    static func storeSuite() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickpad-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        func directory(_ name: String) -> URL {
            root.appendingPathComponent(name)
        }

        T.suite("Encrypted store") {
            T.test("saves and reloads notes") {
                let key = SymmetricKey(size: .bits256)
                let dir = directory("roundtrip")
                var note = Note()
                note.colorID = "mint"
                note.lines = [NoteLine(text: "Passport is in the safe"),
                              NoteLine(text: "Renew by March", isCheckbox: true, isChecked: true)]
                try SecureStore(key: key, directory: dir).save(notes: [note])

                let loaded = try SecureStore(key: key, directory: dir).load()
                T.equal(loaded.notes.count, 1, "one note survives")
                T.equal(loaded.notes[0].lines[0].text, "Passport is in the safe", "text survives")
                T.equal(loaded.notes[0].colorID, "mint", "colour survives")
                T.expect(loaded.notes[0].lines[1].isChecked, "tick survives")
            }

            T.test("writes nothing readable to disk") {
                let dir = directory("opaque")
                let store = SecureStore(key: SymmetricKey(size: .bits256), directory: dir)
                var note = Note()
                note.lines = [NoteLine(text: "wifi password hunter2")]
                try store.save(notes: [note])

                let raw = try Data(contentsOf: store.fileURL)
                T.expect(raw.range(of: Data("hunter2".utf8)) == nil, "note text must not appear in the file")
                T.expect(raw.range(of: Data("wifi".utf8)) == nil, "no plaintext words on disk")
                T.expect(raw.range(of: Data("colorID".utf8)) == nil, "not even JSON keys are readable")
                T.equal(Array(raw.prefix(4)), Array("SPAD".utf8), "file starts with the format magic")
            }

            T.test("keeps the store readable by its owner only") {
                let dir = directory("perms")
                let store = SecureStore(key: SymmetricKey(size: .bits256), directory: dir)
                try store.save(notes: [Note()])
                let attrs = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
                T.equal((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600, "file mode is 600")
            }

            T.test("refuses to open with another key") {
                let dir = directory("wrongkey")
                try SecureStore(key: SymmetricKey(size: .bits256), directory: dir).save(notes: [Note()])
                T.throwsError("a store is unreadable without its key") {
                    _ = try SecureStore(key: SymmetricKey(size: .bits256), directory: dir).load()
                }
            }

            T.test("treats a missing store as empty") {
                let payload = try SecureStore(key: SymmetricKey(size: .bits256),
                                              directory: directory("missing")).load()
                T.expect(payload.notes.isEmpty, "first launch starts empty, not with an error")
            }

            T.test("keeps the previous version as a backup") {
                let dir = directory("backup")
                let store = SecureStore(key: SymmetricKey(size: .bits256), directory: dir)
                try store.save(notes: [Note()])
                try store.save(notes: [Note(), Note()])
                let backup = store.fileURL.appendingPathExtension("bak")
                T.expect(FileManager.default.fileExists(atPath: backup.path), "a .bak generation exists")
            }
        }
    }

    // MARK: - Editing behaviour

    static func editingSuite() {
        func document(_ lines: [NoteLine]) -> NoteDocument {
            var note = Note()
            note.lines = lines
            return NoteDocument(note: note, store: nil)
        }

        T.suite("Note structure") {
            T.test("a new note is exactly 4 x 6 inches") {
                T.equal(NoteGeometry.defaultSize.width, 288, "4in at 72pt/in")
                T.equal(NoteGeometry.defaultSize.height, 432, "6in at 72pt/in")
            }

            T.test("the title is the first non-empty line") {
                var note = Note()
                note.lines = [NoteLine(text: "   "), NoteLine(text: "Call the vet"), NoteLine(text: "later")]
                T.equal(note.title, "Call the vet", "blank lines are skipped")
                T.equal(Note().title, "New note", "an empty note still has a name")
            }

            T.test("colour cycling wraps and unknown ids fall back") {
                T.equal(NotePalette.next(after: NotePalette.all.last!.id), NotePalette.all[0].id, "wraps around")
                T.equal(NotePalette.color(id: "nonsense").id, NotePalette.all[0].id, "unknown id falls back")
            }
        }

        T.suite("Return key") {
            T.test("inserts a line below and focuses it") {
                let doc = document([NoteLine(text: "first"), NoteLine(text: "third")])
                doc.insertLine(after: doc.note.lines[0].id)
                T.equal(doc.note.lines.count, 3, "one line added")
                T.equal(doc.note.lines[1].text, "", "the new line is empty")
                T.equal(doc.focus?.lineID, doc.note.lines[1].id, "focus follows the new line")
                T.equal(doc.focus?.caret, .start, "caret starts at the beginning")
            }

            T.test("continues a checklist") {
                let doc = document([NoteLine(text: "milk", isCheckbox: true)])
                doc.insertLine(after: doc.note.lines[0].id)
                T.equal(doc.note.lines.count, 2, "one line added")
                T.expect(doc.note.lines[1].isCheckbox, "the new row is also a checkbox")
                T.expect(!doc.note.lines[1].isChecked, "and starts unticked")
            }

            T.test("ends the list on an empty checklist item") {
                let doc = document([NoteLine(text: "milk", isCheckbox: true),
                                    NoteLine(text: "", isCheckbox: true)])
                doc.insertLine(after: doc.note.lines[1].id)
                T.equal(doc.note.lines.count, 2, "no extra line is added")
                T.expect(!doc.note.lines[1].isCheckbox, "the empty checkbox becomes a plain line")
            }
        }

        T.suite("Backspace") {
            T.test("unwraps a checkbox before deleting anything") {
                let doc = document([NoteLine(text: "eggs", isCheckbox: true, isChecked: true)])
                doc.backspaceAtStart(of: doc.note.lines[0].id)
                T.equal(doc.note.lines.count, 1, "nothing is removed")
                T.expect(!doc.note.lines[0].isCheckbox, "the box is dropped")
                T.equal(doc.note.lines[0].text, "eggs", "the text is kept")
            }

            T.test("merges into the previous line with the caret at the seam") {
                let doc = document([NoteLine(text: "Hello "), NoteLine(text: "world")])
                doc.backspaceAtStart(of: doc.note.lines[1].id)
                T.equal(doc.note.lines.count, 1, "the lines join")
                T.equal(doc.note.lines[0].text, "Hello world", "text is concatenated")
                T.equal(doc.focus?.caret, .offset(6), "caret sits where the join happened")
            }

            T.test("does nothing on the first line") {
                let doc = document([NoteLine(text: "only")])
                doc.backspaceAtStart(of: doc.note.lines[0].id)
                T.equal(doc.note.lines.count, 1, "the note survives")
                T.equal(doc.note.lines[0].text, "only", "the text survives")
            }
        }

        T.suite("Checkboxes") {
            T.test("toggles both ways and clears the tick when removed") {
                let doc = document([NoteLine(text: "water the plants")])
                let id = doc.note.lines[0].id
                doc.toggleCheckbox(on: id)
                T.expect(doc.note.lines[0].isCheckbox, "becomes a checkbox")
                doc.setChecked(true, on: id)
                T.expect(doc.note.lines[0].isChecked, "can be ticked")
                doc.toggleCheckbox(on: id)
                T.expect(!doc.note.lines[0].isCheckbox, "becomes plain text again")
                T.expect(!doc.note.lines[0].isChecked, "removing the box clears the tick")
            }

            T.test("counts progress") {
                let doc = document([
                    NoteLine(text: "heading"),
                    NoteLine(text: "a", isCheckbox: true, isChecked: true),
                    NoteLine(text: "b", isCheckbox: true),
                    NoteLine(text: "c", isCheckbox: true)
                ])
                T.equal(doc.note.checkboxCount, 3, "three boxes")
                T.equal(doc.note.checkedCount, 1, "one ticked")
            }

            T.test("clearing completed keeps the rest and never empties the note") {
                let doc = document([NoteLine(text: "a", isCheckbox: true, isChecked: true),
                                    NoteLine(text: "b", isCheckbox: true)])
                doc.clearCompleted()
                T.equal(doc.note.lines.map(\.text), ["b"], "only the ticked row goes")

                doc.setChecked(true, on: doc.note.lines[0].id)
                doc.clearCompleted()
                T.equal(doc.note.lines.count, 1, "a note always keeps one line to type into")
                T.equal(doc.note.lines[0].text, "", "and that line is blank")
            }
        }

        T.suite("Paste and navigation") {
            T.test("pasting several lines splits them into rows") {
                let doc = document([NoteLine(text: "", isCheckbox: true)])
                doc.binding(forLine: doc.note.lines[0].id).wrappedValue = "milk\neggs\nbread"
                T.equal(doc.note.lines.map(\.text), ["milk", "eggs", "bread"], "three rows")
                T.expect(doc.note.lines.allSatisfy(\.isCheckbox), "pasted rows inherit the checklist")
                T.expect(!doc.note.lines[2].isChecked, "pasted rows start unticked")
            }

            T.test("arrow navigation stops at the ends") {
                let doc = document([NoteLine(text: "one"), NoteLine(text: "two")])
                doc.moveFocus(from: doc.note.lines[0].id, by: -1)
                T.expect(doc.focus == nil, "up from the first line does nothing")
                doc.moveFocus(from: doc.note.lines[0].id, by: 1)
                T.equal(doc.focus?.lineID, doc.note.lines[1].id, "down moves to the next line")
                doc.focus = nil
                doc.moveFocus(from: doc.note.lines[1].id, by: 1)
                T.expect(doc.focus == nil, "down from the last line does nothing")
            }

            T.test("tapping below the last line reuses a blank trailing line") {
                let doc = document([NoteLine(text: "note"), NoteLine(text: "")])
                doc.focusLastLine()
                T.equal(doc.note.lines.count, 2, "no pile-up of empty lines")
                T.equal(doc.focus?.lineID, doc.note.lines[1].id, "focus lands on the blank line")

                let doc2 = document([NoteLine(text: "note")])
                doc2.focusLastLine()
                T.equal(doc2.note.lines.count, 2, "a line is added when the last one has text")
            }
        }

        T.suite("Appearance and timestamps") {
            T.test("edits touch the timestamp but window moves do not") {
                let doc = document([NoteLine(text: "x")])
                let original = doc.note.updatedAt
                doc.recordFrame(CGRect(x: 10, y: 10, width: 288, height: 432))
                T.equal(doc.note.updatedAt, original, "moving a window is not an edit")
                doc.setColor("rose")
                T.expect(doc.note.updatedAt > original, "recolouring is an edit")
                T.equal(doc.note.colorID, "rose", "the colour is applied")
            }

            T.test("font size is clamped to a readable range") {
                let doc = document([NoteLine(text: "x")])
                doc.setFontSize(400)
                T.equal(doc.note.fontSize, 28, "upper bound")
                doc.setFontSize(1)
                T.equal(doc.note.fontSize, 10, "lower bound")
            }

            T.test("a note dragged off-screen is pulled back into view") {
                let clamped = NoteGeometry.clampToScreens(CGRect(x: -9000, y: -9000, width: 288, height: 432))
                T.expect(clamped.minX > -9000, "the note is not left off-screen")
                T.equal(clamped.size, NoteGeometry.defaultSize, "its size is preserved")
            }
        }
    }
}
