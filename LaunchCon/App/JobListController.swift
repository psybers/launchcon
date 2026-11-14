import AppKit

/// Main content: table of jobs with status coloring.
final class JobListController: NSViewController {

    private let store: JobStore
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No jobs")

    var onSelectionChange: ((Job?) -> Void)?

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
        emptyLabel.stringValue = store.isLoading ? "Loading…" : "No jobs"
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

        // Color-code: green = running, red = disabled, secondary = otherwise.
        if job.pid != nil {
            textField?.textColor = .systemGreen
        } else if job.isDisabled {
            textField?.textColor = .systemRed
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
