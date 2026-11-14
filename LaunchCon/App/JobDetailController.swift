import AppKit

/// Right-hand detail placeholder: shows basic info for the selected job.
final class JobDetailController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var valueLabels: [String: NSTextField] = [:]

    private static let rows: [(key: String, title: String)] = [
        ("label", "Label"),
        ("domain", "Domain"),
        ("state", "State"),
        ("pid", "PID"),
        ("exitStatus", "Last exit status"),
        ("path", "Plist path"),
    ]

    override func loadView() {
        let container = NSView()

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for row in Self.rows {
            let titleLabel = NSTextField(labelWithString: row.title)
            titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            titleLabel.textColor = .secondaryLabelColor

            let valueLabel = NSTextField(wrappingLabelWithString: "—")
            valueLabel.font = .systemFont(ofSize: 13)
            valueLabel.maximumNumberOfLines = 0

            let rowStack = NSStackView(views: [titleLabel, valueLabel])
            rowStack.orientation = .vertical
            rowStack.alignment = .leading
            rowStack.spacing = 2

            stackView.addArrangedSubview(rowStack)
            valueLabels[row.key] = valueLabel
        }

        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        view = container
    }

    func show(job: Job?) {
        guard let job else {
            for (_, label) in valueLabels { label.stringValue = "—" }
            return
        }
        valueLabels["label"]?.stringValue = job.label
        valueLabels["domain"]?.stringValue = job.domain.rawValue
        valueLabels["state"]?.stringValue = stateText(for: job)
        valueLabels["pid"]?.stringValue = job.pid.map(String.init) ?? "—"
        valueLabels["exitStatus"]?.stringValue = job.lastExitStatus.map(String.init) ?? "—"
        valueLabels["path"]?.stringValue = job.plistPath ?? "—"
    }

    private func stateText(for job: Job) -> String {
        if job.pid != nil { return "Running" }
        if job.isDisabled { return "Disabled" }
        if job.isLoaded { return "Loaded" }
        return "Not loaded"
    }
}
