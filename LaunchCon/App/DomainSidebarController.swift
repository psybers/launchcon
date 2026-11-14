import AppKit

/// Left sidebar: domain group picker, search field, and refresh button.
final class DomainSidebarController: NSViewController {

    private let store: JobStore
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

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

        searchField.placeholderString = "Filter jobs"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filterChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("domain"))
        column.title = "Domain"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(domainDoubleClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)

        let stack = NSStackView(views: [searchField, scrollView, refreshButton])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.reloadData()
        selectRow(for: store.selectedGroup)
    }

    @objc private func filterChanged() {
        store.filterText = searchField.stringValue
    }

    @objc private func refreshClicked() {
        store.reload()
    }

    @objc private func domainDoubleClicked() {
        refreshClicked()
    }

    private func selectRow(for group: JobStore.DomainGroup?) {
        guard let group, let index = store.groups.firstIndex(of: group) else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
}

extension DomainSidebarController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        store.groups.count
    }
}

extension DomainSidebarController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("domainCell")
        var cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
        if cell == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
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
        cell?.textField?.stringValue = store.groups[row].title
        cell?.textField?.textColor = store.groups[row].id == store.selectedGroup?.id
            ? .labelColor
            : .secondaryLabelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < store.groups.count else { return }
        store.selectedGroup = store.groups[row]
        tableView.reloadData() // refresh selection styling
    }
}
