import AppKit

final class MainWindowController: NSWindowController {

    private let store = JobStore()
    private var jobList: JobListController!
    private var detail: JobDetailController!
    private var editorWindowControllers: [JobEditorWindowController] = []
    private var activeEditor: JobEditorWindowController?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaunchCon"

        let sidebar = DomainSidebarController(store: store)
        let list = JobListController(store: store)
        jobList = list
        let detailVC = JobDetailController()
        detail = detailVC

        list.onSelectionChange = { [weak detailVC] job in
            detailVC?.show(job: job)
        }

        let splitViewController = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        // Fixed content-fit widths: the job list absorbs all remaining space.
        sidebarItem.minimumThickness = DomainSidebarController.fitWidth(for: store.groups)
        sidebarItem.maximumThickness = sidebarItem.minimumThickness
        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = JobDetailController.fitWidth
        detailItem.maximumThickness = detailItem.minimumThickness
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: list))
        splitViewController.addSplitViewItem(detailItem)

        window.contentViewController = splitViewController
        // Assigning a contentViewController lets AppKit resize the window to the
        // view's fitting size; enforce our desired size afterwards.
        window.setContentSize(NSSize(width: 1100, height: 640))
        window.center()
        super.init(window: window)

        list.onJobAction = { [weak self] action, job in
            self?.performJobAction(action, on: job)
        }
        detailVC.onEdit = { [weak self] job in
            self?.openEditor(for: job)
        }
        list.onDoubleClick = { [weak self] job in
            self?.openEditor(for: job)
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

    // MARK: - Plist editor

    func openEditor(for job: Job) {
        guard let plistPath = job.plistPath else { return }
        let url = URL(fileURLWithPath: plistPath)
        guard let dict = job.plist ?? Plist.load(url) else {
            showAlert(title: "Cannot edit", message: "Could not read \(plistPath)")
            return
        }
        let document = PlistDocument(url: url, contents: dict)
        let editor = JobEditorWindowController(document: document, jobLabel: job.label) { [weak self] in
            self?.editorDidSave(document: document, job: job)
        }
        editor.onClose = { [weak self] in
            self?.editorWindowControllers.removeAll { $0 === editor }
        }
        editorWindowControllers.append(editor)
        activeEditor = editor
        editor.showWindow(nil)
    }

    private func editorDidSave(document: PlistDocument, job: Job) {
        store.reload()
        guard job.isLoaded else { return }

        let alert = NSAlert()
        alert.messageText = "Reload \(job.label)?"
        alert.informativeText = "The plist changed. Reload the job to apply the changes?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                try await store.reloadService(
                    label: job.label,
                    domain: job.domain,
                    plistPath: document.url.path
                )
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Reload failed", message: "\(error)")
                }
            }
        }
    }

    // MARK: - New job

    @objc func newJob(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "New Job"
        alert.informativeText = "Enter a label for the new launch agent (e.g. com.example.myagent)."
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "com.example.myagent"
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let label = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty,
              label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" })
        else {
            showAlert(title: "Invalid label", message: "Labels may contain letters, numbers, dots, dashes and underscores.")
            return
        }

        let url = JobStore.homeLibrary("LaunchAgents", "\(label).plist")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            showAlert(title: "File exists", message: "\(url.path) already exists.")
            return
        }

        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/echo", "Hello from \(label)"],
            "RunAtLoad": false,
        ]
        do {
            try Plist.save(contents, to: url)
        } catch {
            showAlert(title: "Create failed", message: "\(error)")
            return
        }

        let job = Job(
            label: label,
            pid: nil,
            lastExitStatus: nil,
            domain: .guiCurrentUser,
            plistPath: url.path,
            isLoaded: false,
            isDisabled: false,
            plist: contents
        )
        openEditor(for: job)
        store.reload()
    }

    // MARK: - Editor save (menu)

    @objc func saveEditor(_ sender: Any?) {
        activeEditor?.saveDocument()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
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
        if menuItem.action == #selector(newJob(_:)) { return true }
        if menuItem.action == #selector(saveEditor(_:)) { return activeEditor != nil }
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
