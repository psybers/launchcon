import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindowController = MainWindowController()
        NSApp.mainMenu = buildMainMenu(jobTarget: mainWindowController)
        mainWindowController?.showWindow(nil)
        DispatchQueue.main.async { [weak mainWindowController] in
            mainWindowController?.applyInitialSplitPositionsIfNeeded()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu(jobTarget: MainWindowController?) -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About LaunchCon",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LaunchCon",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Edit menu (needed for text fields: cut/copy/paste/select all)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSStandardKeyBindingResponding.selectAll(_:)), keyEquivalent: "a")

        // Job menu — actions apply to the selected job in the main window.
        let jobMenuItem = NSMenuItem()
        mainMenu.addItem(jobMenuItem)
        let jobMenu = NSMenu(title: "Job")
        jobMenuItem.submenu = jobMenu

        func jobItem(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = jobTarget
            return item
        }
        jobMenu.addItem(jobItem("New Job…", #selector(MainWindowController.newJob(_:)), "n"))
        jobMenu.addItem(.separator())
        jobMenu.addItem(jobItem("Load", #selector(MainWindowController.jobLoad(_:))))
        jobMenu.addItem(jobItem("Unload", #selector(MainWindowController.jobUnload(_:))))
        jobMenu.addItem(.separator())
        jobMenu.addItem(jobItem("Enable", #selector(MainWindowController.jobEnable(_:))))
        jobMenu.addItem(jobItem("Disable", #selector(MainWindowController.jobDisable(_:))))
        jobMenu.addItem(.separator())
        jobMenu.addItem(jobItem("Start", #selector(MainWindowController.jobStart(_:))))
        jobMenu.addItem(jobItem("Stop", #selector(MainWindowController.jobStop(_:))))
        jobMenu.addItem(.separator())
        jobMenu.addItem(jobItem("Refresh", #selector(MainWindowController.jobRefresh(_:)), "r"))

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")

        NSApp.windowsMenu = windowMenu
        return mainMenu
    }
}
