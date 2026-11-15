import AppKit

/// NSTableView that selects the row under the cursor before showing the
/// context menu, so menu actions apply to the clicked job.
private final class JobTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

/// Main content: table of jobs with status coloring.
final class JobListController: NSViewController {

    private let store: JobStore
    private let tableView = JobTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No jobs")

    var onSelectionChange: ((Job?) -> Void)?
    /// Called with the job action and the selected job when a menu item is chosen.
    var onJobAction: ((JobStore.JobAction, Job) -> Void)?
    /// Called when a row is double-clicked.
    var onDoubleClick: ((Job) -> Void)?

    init(store: JobStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()

        for (id, title, width) in [
            ("label", "Label", 280.0),
            ("pid", "PID", 70.0),
            ("status", "Status", 80.0),
            ("domain", "Domain", 160.0),
            ("path", "Path", 300.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = 40
            column.maxWidth = .greatestFiniteMagnitude
            tableView.addTableColumn(column)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = buildJobMenu()
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.usesAutomaticRowHeights = true
        tableView.rowSizeStyle = .default

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        container.addSubview(scrollView)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.onChange = { [weak self] in
            self?.refresh()
        }
        store.reload()
        refresh()
    }

    func refresh() {
        tableView.reloadData()
        emptyLabel.isHidden = !store.visibleJobs.isEmpty || store.isLoading
        emptyLabel.stringValue = store.isLoading ? "Loading…" : (store.loadError ?? "No jobs")
    }

    // MARK: - Job actions

    private func buildJobMenu() -> NSMenu {
        let menu = NSMenu()

        func addItem(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        addItem("Load", #selector(jobLoad(_:)))
        addItem("Unload", #selector(jobUnload(_:)))
        menu.addItem(.separator())
        addItem("Enable", #selector(jobEnable(_:)))
        addItem("Disable", #selector(jobDisable(_:)))
        menu.addItem(.separator())
        addItem("Start", #selector(jobStart(_:)))
        addItem("Stop", #selector(jobStop(_:)))
        menu.addItem(.separator())
        addItem("Refresh", #selector(jobRefresh(_:)))
        return menu
    }

    private func performAction(_ action: JobStore.JobAction) {
        guard let job = selectedJob() else { return }
        onJobAction?(action, job)
    }

    @objc private func rowDoubleClicked() {
        guard let job = selectedJob() else { return }
        onDoubleClick?(job)
    }

    @objc private func jobLoad(_ sender: Any?) { performAction(.load) }
    @objc private func jobUnload(_ sender: Any?) { performAction(.unload) }
    @objc private func jobEnable(_ sender: Any?) { performAction(.enable) }
    @objc private func jobDisable(_ sender: Any?) { performAction(.disable) }
    @objc private func jobStart(_ sender: Any?) { performAction(.start) }
    @objc private func jobStop(_ sender: Any?) { performAction(.stop) }
    @objc private func jobRefresh(_ sender: Any?) { store.reload() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(jobRefresh(_:)) { return true }
        guard let job = selectedJob() else { return false }
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

    func selectedJob() -> Job? {
        let row = tableView.selectedRow
        guard row >= 0, row < store.visibleJobs.count else { return nil }
        return store.visibleJobs[row]
    }
}

extension JobListController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        store.visibleJobs.count
    }
}

extension JobListController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let job = store.visibleJobs[row]

        let cellID = NSUserInterfaceItemIdentifier("cell-\(column.identifier.rawValue)")
        var cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
        if cell == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell = NSTableCellView()
            cell?.identifier = cellID
            cell?.addSubview(textField)
            cell?.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
            ])
        }

        let textField = cell?.textField
        switch column.identifier.rawValue {
        case "label":
            textField?.stringValue = job.label
        case "pid":
            textField?.stringValue = job.pid.map(String.init) ?? "—"
        case "status":
            textField?.stringValue = statusText(for: job)
        case "domain":
            textField?.stringValue = job.domain.rawValue
        case "path":
            textField?.stringValue = job.plistPath ?? "—"
        default:
            break
        }

        // Color-code: green = running, red = disabled, orange = not loaded.
        if job.pid != nil {
            textField?.textColor = .systemGreen
        } else if job.isDisabled {
            textField?.textColor = .systemRed
        } else if !job.isLoaded {
            textField?.textColor = .systemOrange
        } else {
            textField?.textColor = .labelColor
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelectionChange?(selectedJob())
    }

    private func statusText(for job: Job) -> String {
        if job.pid != nil { return "Running" }
        if job.isDisabled { return "Disabled" }
        if job.isLoaded { return job.lastExitStatus.map { "Exit \($0)" } ?? "Loaded" }
        return "Not loaded"
    }
}
