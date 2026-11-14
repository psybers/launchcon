import AppKit

final class MainWindowController: NSWindowController {

    private let store = JobStore()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaunchController"

        let sidebar = DomainSidebarController(store: store)
        let jobList = JobListController(store: store)
        let detail = JobDetailController()

        jobList.onSelectionChange = { [weak detail] job in
            detail?.show(job: job)
        }

        let splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: sidebar))
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: jobList))
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: detail))

        // Sidebar: narrow, fixed-ish. Detail pane: resizable but with a floor.
        let sidebarItem = splitViewController.splitViewItems[0]
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        splitViewController.splitViewItems[2].minimumThickness = 220

        window.contentViewController = splitViewController
        // Assigning a contentViewController lets AppKit resize the window to the
        // view's fitting size; enforce our desired size afterwards.
        window.setContentSize(NSSize(width: 1100, height: 640))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
