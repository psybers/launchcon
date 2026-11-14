import AppKit

final class MainWindowController: NSWindowController {

    private let store = JobStore()
    private var jobList: JobListController!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaunchController"

        let sidebar = DomainSidebarController(store: store)
        let list = JobListController(store: store)
        jobList = list
        let detail = JobDetailController()

        list.onSelectionChange = { [weak detail] job in
            detail?.show(job: job)
        }

        let splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: sidebar))
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: list))
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

        list.onJobAction = { [weak self] action, job in
            self?.performJobAction(action, on: job)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Job actions

    private func performJobAction(_ action: JobStore.JobAction, on job: Job) {
        if action == .unload || action == .stop {
            let alert = NSAlert()
            alert.messageText = "\(action == .unload ? "Unload" : "Stop") \(job.label)?"
            alert.informativeText = action == .unload
                ? "This removes the job from the launchd domain until it is loaded again."
                : "This sends SIGTERM to the running process."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: action == .unload ? "Unload" : "Stop")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }

        Task {
            do {
                try await store.perform(action, on: job)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Action failed"
                    alert.informativeText = "\(error)"
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private func selectedJobForMenu() -> Job? {
        jobList.selectedJob()
    }

    @objc func jobLoad(_ sender: Any?) { actionForSelected(.load) }
    @objc func jobUnload(_ sender: Any?) { actionForSelected(.unload) }
    @objc func jobEnable(_ sender: Any?) { actionForSelected(.enable) }
    @objc func jobDisable(_ sender: Any?) { actionForSelected(.disable) }
    @objc func jobStart(_ sender: Any?) { actionForSelected(.start) }
    @objc func jobStop(_ sender: Any?) { actionForSelected(.stop) }
    @objc func jobRefresh(_ sender: Any?) { store.reload() }

    private func actionForSelected(_ action: JobStore.JobAction) {
        guard let job = selectedJobForMenu() else { return }
        performJobAction(action, on: job)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(jobRefresh(_:)) { return true }
        guard let job = selectedJobForMenu() else { return false }
        switch menuItem.action {
        case #selector(jobLoad(_:)):
            return !job.isLoaded && job.plistPath != nil
        case #selector(jobUnload(_:)):
            return job.isLoaded
        case #selector(jobEnable(_:)):
            return job.isLoaded && job.isDisabled
        case #selector(jobDisable(_:)):
            return job.isLoaded && !job.isDisabled
        case #selector(jobStart(_:)), #selector(jobStop(_:)):
            return job.isLoaded
        default:
            return true
        }
    }
}
