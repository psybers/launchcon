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
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = 40
            column.maxWidth = .greatestFiniteMagnitude
            // Only the label column absorbs width changes; the rest keep
            // their widths but remain user-resizable.
            column.resizingMask = id == "label"
                ? [.autoresizingMask, .userResizingMask]
                : [.userResizingMask]
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            tableView.addTableColumn(column)
        }
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = buildJobMenu()
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        // Not usesAutomaticRowHeights: that makes the table size cells by
        // their fitting width, so long labels overflow into the next columns.
        tableView.rowHeight = 22
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
        restoreTableState()
        store.reload()
        refresh()
        // Column widths only change via drags (no notification), so save on quit.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveTableState),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    /// Column widths and sort order persisted under UserDefaults.
    private enum TableDefaultsKey {
        static let columnWidths = "JobList.columnWidths"
        static let sortDescriptors = "JobList.sortDescriptors"
    }

    private func restoreTableState() {
        if let widths = UserDefaults.standard.dictionary(forKey: TableDefaultsKey.columnWidths) as? [String: Double] {
            for column in tableView.tableColumns {
                if let width = widths[column.identifier.rawValue] {
                    column.width = width
                }
            }
        }
        if let saved = UserDefaults.standard.array(forKey: TableDefaultsKey.sortDescriptors) as? [[String: Any]] {
            tableView.sortDescriptors = saved.compactMap { entry in
                guard let key = entry["key"] as? String else { return nil }
                return NSSortDescriptor(key: key, ascending: entry["ascending"] as? Bool ?? true)
            }
        }
    }

    @objc private func saveTableState() {
        var widths: [String: Double] = [:]
        for column in tableView.tableColumns {
            widths[column.identifier.rawValue] = column.width
        }
        UserDefaults.standard.set(widths, forKey: TableDefaultsKey.columnWidths)
        UserDefaults.standard.set(
            tableView.sortDescriptors.map { ["key": $0.key ?? "", "ascending": $0.ascending] },
            forKey: TableDefaultsKey.sortDescriptors
        )
    }

    func refresh() {
        // Remember the selection by label — reloadData can drop it or leave
        // it pointing at a different row when the job set changes.
        let selectedLabel = selectedJob()?.label
        tableView.reloadData()
        emptyLabel.isHidden = !store.visibleJobs.isEmpty || store.isLoading
        emptyLabel.stringValue = store.isLoading ? "Loading…" : (store.loadError ?? "No jobs")
        if let selectedLabel, selectedJob()?.label != selectedLabel,
           let row = store.visibleJobs.firstIndex(where: { $0.label == selectedLabel }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        // reloadData preserves the selection silently — re-emit it so the
        // detail pane refreshes with the new job objects (plist, status).
        onSelectionChange?(selectedJob())
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
        // doubleAction also fires for header clicks; clickedRow is -1 then.
        guard tableView.clickedRow >= 0, let job = selectedJob() else { return }
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
        textField?.toolTip = nil
        switch column.identifier.rawValue {
        case "label":
            textField?.stringValue = job.label
            // Tooltip with the full label only when it doesn't fit the column.
            if let textField {
                let font = textField.font ?? .systemFont(ofSize: NSFont.systemFontSize)
                let textWidth = (job.label as NSString).size(withAttributes: [.font: font]).width
                if textWidth > column.width - 8 {
                    textField.toolTip = job.label
                }
            }
        case "pid":
            textField?.stringValue = job.pid.map(String.init) ?? "—"
        case "status":
            textField?.stringValue = job.statusText
        case "domain":
            textField?.stringValue = job.domain.rawValue
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

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        store.sortDescriptors = tableView.sortDescriptors
        saveTableState()
    }
}
