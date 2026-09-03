import AppKit

/// The app is built without a nib, so the main menu is assembled by hand.
/// The Edit menu matters more than it looks: the standard selectors are what
/// give the note editors undo, copy/paste and Select All.
enum MainMenu {
    @MainActor
    static func install() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Stick Pad", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Stick Pad", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Stick Pad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Note", action: #selector(AppDelegate.newNote(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "All Notes…", action: #selector(AppDelegate.showNotesList(_:)), keyEquivalent: "0")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save Note As…", action: #selector(AppDelegate.saveFrontNoteAs(_:)), keyEquivalent: "s")
        let exportAll = fileMenu.addItem(withTitle: "Save All Notes to a Folder…", action: #selector(AppDelegate.exportAllNotes(_:)), keyEquivalent: "s")
        exportAll.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Note", action: #selector(AppDelegate.closeFrontNote(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Hide All Notes", action: #selector(AppDelegate.hideAllNotes(_:)), keyEquivalent: "")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Note
        let noteItem = NSMenuItem()
        let noteMenu = NSMenu(title: "Note")
        noteMenu.addItem(withTitle: "Toggle Checkbox", action: #selector(AppDelegate.toggleCheckboxOnFrontNote(_:)), keyEquivalent: "l")
        noteMenu.addItem(withTitle: "Next Colour", action: #selector(AppDelegate.cycleFrontNoteColor(_:)), keyEquivalent: "k")
        noteMenu.addItem(withTitle: "Keep on Top", action: #selector(AppDelegate.togglePinOnFrontNote(_:)), keyEquivalent: "t")
        noteMenu.addItem(withTitle: "Reset to 4 × 6 inches", action: #selector(AppDelegate.resetFrontNoteSize(_:)), keyEquivalent: "r")
        noteMenu.addItem(.separator())
        let delete = noteMenu.addItem(withTitle: "Delete Note…", action: #selector(AppDelegate.deleteFrontNote(_:)), keyEquivalent: "\u{8}")
        delete.keyEquivalentModifierMask = [.command]
        noteItem.submenu = noteMenu
        main.addItem(noteItem)

        // Security
        let secItem = NSMenuItem()
        let secMenu = NSMenu(title: "Security")
        secMenu.addItem(withTitle: "Export Encryption Key…", action: #selector(AppDelegate.exportKey(_:)), keyEquivalent: "")
        secMenu.addItem(withTitle: "Import Encryption Key…", action: #selector(AppDelegate.importKey(_:)), keyEquivalent: "")
        secMenu.addItem(.separator())
        secMenu.addItem(withTitle: "Save Encrypted Backup…", action: #selector(AppDelegate.saveEncryptedBackup(_:)), keyEquivalent: "")
        secMenu.addItem(withTitle: "Restore from Encrypted Backup…", action: #selector(AppDelegate.restoreEncryptedBackup(_:)), keyEquivalent: "")
        secMenu.addItem(.separator())
        secMenu.addItem(withTitle: "Reveal Encrypted Store in Finder", action: #selector(AppDelegate.revealStore(_:)), keyEquivalent: "")
        secItem.submenu = secMenu
        main.addItem(secItem)

        // Window
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Bring Notes to Front", action: #selector(AppDelegate.bringNotesToFront(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Show All Notes", action: #selector(AppDelegate.showAllNotes(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
