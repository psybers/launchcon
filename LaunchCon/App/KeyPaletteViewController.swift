import AppKit

/// Popover content: a searchable list of every launchd plist key in the
/// editor schema, with descriptions and current values. Clicking a row asks
/// the editor to add the key (with its default value, when defined) or
/// focus its row.
final class KeyPaletteViewController: NSViewController {

    private let document: PlistDocument
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    private var keys: [JobKeySchema] = []

    /// Called with the schema key the user clicked.
    var onPick: ((String) -> Void)?

    init(document: PlistDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()

        searchField.placeholderString = "Filter keys"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filterChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        for (id, title, width) in [
            ("title", "Name", 140.0),
            ("key", "Key", 180.0),
            ("value", "Value", 110.0),
            ("summary", "Description", 240.0),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = 50
            column.maxWidth = .greatestFiniteMagnitude
            column.resizingMask = id == "summary"
                ? [.autoresizingMask, .userResizingMask]
                : [.userResizingMask]
            tableView.addTableColumn(column)
        }
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.rowHeight = 22
        tableView.usesAutomaticRowHeights = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [searchField, scrollView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
        preferredContentSize = NSSize(width: 700, height: 340)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyFilter("")
    }

    /// Recomputes the filtered rows (e.g. after the editor added a key).
    func reload() {
        applyFilter(searchField.stringValue)
    }

    @objc private func filterChanged() {
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        keys = q.isEmpty
            ? JobKeySchema.all
            : JobKeySchema.all.filter {
                $0.key.lowercased().contains(q)
                    || $0.title.lowercased().contains(q)
                    || $0.summary.lowercased().contains(q)
            }
        tableView.reloadData()
    }

    /// Short display of the key's current value in the document.
    private func shortValue(for key: String) -> String {
        guard let value = document.value(forKey: key) else { return "—" }
        switch value {
        case let string as String:
            return string.isEmpty ? "(empty)" : string
        case is [String: Any], is [Any]:
            return "(complex)"
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? (number.boolValue ? "true" : "false")
                : number.stringValue
        default:
            return "\(value)"
        }
    }
}

extension KeyPaletteViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        keys.count
    }
}

extension KeyPaletteViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let schema = keys[row]

        let cellID = NSUserInterfaceItemIdentifier("palette-\(column.identifier.rawValue)")
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
        case "title":
            textField?.stringValue = schema.title
            textField?.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        case "key":
            textField?.stringValue = schema.key
            textField?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        case "value":
            textField?.stringValue = shortValue(for: schema.key)
            textField?.textColor = document.value(forKey: schema.key) == nil
                ? .secondaryLabelColor : .labelColor
        default:
            textField?.stringValue = schema.summary
            textField?.textColor = .secondaryLabelColor
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < keys.count else { return }
        onPick?(keys[row].key)
    }
}
