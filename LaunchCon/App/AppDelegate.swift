import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        buildDebugMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildDebugMenu() {
        let debugMenu = NSMenu(title: "Debug")
        let dumpItem = NSMenuItem(
            title: "Dump Jobs (gui/\(getuid()))",
            action: #selector(dumpJobs),
            keyEquivalent: ""
        )
        dumpItem.target = self
        debugMenu.addItem(dumpItem)

        guard let appMenu = NSApp.mainMenu?.item(withTitle: "LaunchCon")?.submenu else { return }
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Debug", action: nil, keyEquivalent: "").withSubmenu(debugMenu))
    }

    @objc private func dumpJobs() {
        Task {
            do {
                let jobs = try await Launchctl.list(domain: .guiCurrentUser)
                for job in jobs {
                    print("\(job.pid.map(String.init) ?? "-")\t\(job.lastExitStatus.map(String.init) ?? "-")\t\(job.label)")
                }
                print("--- \(jobs.count) jobs ---")
            } catch {
                print("launchctl error: \(error)")
            }
        }
    }
}

private extension NSMenuItem {
    func withSubmenu(_ menu: NSMenu) -> NSMenuItem {
        self.submenu = menu
        return self
    }
}
