import AppKit

final class MainWindowController: NSWindowController {

    private let store = JobStore()
    private var jobList: JobListController!
    private var detail: JobDetailController!
    private var splitView: NSSplitView!
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

        // A plain NSSplitView manages pane frames directly, so initial
        // divider positions and drag constraints behave predictably (unlike
        // NSSplitViewController's constraint-driven layout).
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        self.splitView = splitView

        let container = NSViewController()
        container.addChild(sidebar)
        container.addChild(list)
        container.addChild(detailVC)

        // NSSplitView takes each pane's initial size from its existing frame,
        // so give every pane an explicit frame: sidebar and detail at their
        // fit widths, the job list taking the remainder. Only the list gets a
        // flexible width so it absorbs window resizes; the outer panes keep
        // their (draggable) widths.
        let paneWidths: [(NSViewController, CGFloat)] = [
            (sidebar, Self.sidebarMinWidth),
            (list, 1100 - Self.sidebarMinWidth - JobDetailController.fitWidth),
            (detailVC, JobDetailController.fitWidth),
        ]
        var x: CGFloat = 0
        for (child, width) in paneWidths {
            child.view.translatesAutoresizingMaskIntoConstraints = false
            child.view.frame = NSRect(x: x, y: 0, width: width, height: 640)
            child.view.autoresizingMask = child === list ? [.width, .height] : [.height]
            splitView.addSubview(child.view)
            x += width
        }
        container.view = splitView
        splitView.autoresizingMask = [.width, .height]
        splitView.translatesAutoresizingMaskIntoConstraints = true

        window.contentViewController = container
        window.minSize = NSSize(
            width: Self.sidebarMinWidth + Self.listMinWidth + JobDetailController.fitWidth,
            height: 420
        )
        // Assigning a contentViewController lets AppKit resize the window to the
        // view's fitting size; enforce our desired size afterwards.
        window.setContentSize(NSSize(width: 1100, height: 640))
        window.center()
        super.init(window: window)
        splitView.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowResized(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )

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

    /// Minimum pane widths used for divider drag constraints and the window's
    /// minimum size.
    private static let listMinWidth: CGFloat = 240
    private static var sidebarMinWidth: CGFloat {
        DomainSidebarController.fitWidth(for: JobStore.defaultGroups())
    }

    private var didApplyInitialSplitPositions = false

    // windowDidLoad never fires for this programmatically created window, so
    // initial pane positions are applied once the window is on screen —
    // triggered by `applyInitialSplitPositionsIfNeeded` from AppDelegate and
    // by the didResize observer below.
    @objc private func windowResized(_ notification: Notification) {
        applyInitialSplitPositionsIfNeeded()
    }

    func applyInitialSplitPositionsIfNeeded() {
        guard !didApplyInitialSplitPositions, splitView.bounds.width > 0 else { return }
        didApplyInitialSplitPositions = true
        applyInitialSplitPositions()
    }

    /// Opens with the sidebar and detail panes at their fit widths and the job
    /// list taking the remaining space.
    private func applyInitialSplitPositions() {
        splitView.layoutSubtreeIfNeeded()
        let width = splitView.bounds.width
        guard width > 0, splitView.subviews.count >= 3 else { return }
        // Set the right divider first: each setPosition re-lays out the other
        // dividers from their stored positions, so the left one must be last.
        splitView.setPosition(width - JobDetailController.fitWidth, ofDividerAt: 1)
        splitView.setPosition(Self.sidebarMinWidth, ofDividerAt: 0)
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

extension MainWindowController: NSSplitViewDelegate {
    /// Keeps each pane above its minimum width while dragging a divider.
    /// Divider 0 sits between sidebar and job list; divider 1 between job
    /// list and detail.
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMin: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        switch dividerIndex {
        case 0:
            return Self.sidebarMinWidth
        case 1:
            let sidebarRight = splitView.subviews.first?.frame.maxX ?? Self.sidebarMinWidth
            return sidebarRight + Self.listMinWidth
        default:
            return proposedMin
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMax: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let width = splitView.bounds.width
        switch dividerIndex {
        case 0:
            return width - Self.listMinWidth - JobDetailController.fitWidth
        case 1:
            return width - JobDetailController.fitWidth
        default:
            return proposedMax
        }
    }
}
