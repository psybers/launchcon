import AppKit

/// Flipped stack view: arranged subviews lay out top-to-bottom, so extra
/// space in a stretched document goes to the bottom, not the top.
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// Right-hand inspector: Info (plist summary + diagnostics), live launchd
/// state, log tail, and raw plist XML — switched by a segmented control.
final class JobDetailController: NSViewController {

    private enum Tab: Int, CaseIterable {
        case info, state, logs, xml
        var title: String {
            switch self {
            case .info: return "Info"
            case .state: return "State"
            case .logs: return "Logs"
            case .xml: return "XML"
            }
        }
    }

    private let segmented = NSSegmentedControl()
    private var selectedTab: Tab = .info

    // Info tab
    private let infoScroll = NSScrollView()
    private let infoStack = FlippedStackView()
    private var valueLabels: [String: NSTextField] = [:]
    private let diagnosticsContainer = NSStackView()
    private let editButton = NSButton(title: "Edit Property List…", target: nil, action: nil)

    // State tab
    private let stateScroll = NSScrollView()
    private let stateOuterStack = FlippedStackView()
    private let stateRowsStack = NSStackView()
    private let stateStatusLabel = NSTextField(labelWithString: "")
    private let stateRefreshButton = NSButton(title: "Refresh", target: nil, action: nil)

    // Logs tab
    private let logsContainer = NSView()
    private let logSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let logStatusLabel = NSTextField(labelWithString: "")
    private let logTextView = NSTextView()
    private let logScroll = NSScrollView()
    private var logTimer: Timer?

    // XML tab
    private let xmlTextView = NSTextView()
    private let xmlScroll = NSScrollView()

    private var currentJob: Job?
    var onEdit: ((Job) -> Void)?

    /// Approximate width that fits the info row titles plus a typical value.
    static var fitWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let maxTitle = infoRowTitles.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return min(max(ceil(maxTitle) + 170, 260), 400)
    }

    private static let infoRowTitles = [
        "Label", "Domain", "State", "PID", "Last exit status", "Plist path",
    ]

    private static let infoRows: [(key: String, title: String)] = [
        ("label", "Label"),
        ("domain", "Domain"),
        ("state", "State"),
        ("pid", "PID"),
        ("exitStatus", "Last exit status"),
        ("path", "Plist path"),
    ]

    // MARK: - View setup

    override func loadView() {
        let container = NSView()

        segmented.segmentStyle = .rounded
        segmented.trackingMode = .selectOne
        segmented.segmentCount = Tab.allCases.count
        for (index, tab) in Tab.allCases.enumerated() {
            segmented.setLabel(tab.title, forSegment: index)
            segmented.setWidth(56, forSegment: index)
        }
        segmented.selectedSegment = Tab.info.rawValue
        segmented.target = self
        segmented.action = #selector(tabChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        buildInfoTab()
        buildStateTab()
        buildLogsTab()
        buildXMLTab()

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        for scroll in [infoScroll, stateScroll, logsContainer, xmlScroll] {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: content.topAnchor),
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }

        // Manual layout: the segmented control sits at the top and the tab
        // content fills all remaining height (a stack view would give the
        // scroll views only their tiny fitting height).
        segmented.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(segmented)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            segmented.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            segmented.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        view = container
        applyTabVisibility()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Poll log files once a second while the Logs tab is visible.
        logTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLogsIfNeeded()
        }
    }

    // MARK: - Info tab

    private func buildInfoTab() {
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 10
        infoStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 16, right: 6)
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        for row in Self.infoRows {
            let titleLabel = NSTextField(labelWithString: row.title)
            titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            titleLabel.textColor = .secondaryLabelColor

            let valueLabel = NSTextField(labelWithString: "—")
            valueLabel.font = .systemFont(ofSize: 13)
            valueLabel.maximumNumberOfLines = 1
            valueLabel.lineBreakMode = .byTruncatingMiddle

            let rowStack = NSStackView(views: [titleLabel, valueLabel])
            rowStack.orientation = .vertical
            rowStack.alignment = .leading
            rowStack.spacing = 2

            infoStack.addArrangedSubview(rowStack)
            valueLabels[row.key] = valueLabel
        }

        diagnosticsContainer.orientation = .vertical
        diagnosticsContainer.alignment = .leading
        diagnosticsContainer.spacing = 6
        diagnosticsContainer.isHidden = true
        infoStack.insertArrangedSubview(diagnosticsContainer, at: 0)

        editButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(editClicked)
        editButton.alignment = .left
        infoStack.addArrangedSubview(editButton)

        embedInScroll(infoScroll, content: infoStack)
    }

    private func rebuildDiagnostics(for job: Job?) {
        for view in diagnosticsContainer.arrangedSubviews {
            diagnosticsContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let job else {
            diagnosticsContainer.isHidden = true
            return
        }

        let diagnostics = JobValidator.validate(job)
        guard !diagnostics.isEmpty else {
            diagnosticsContainer.isHidden = true
            return
        }

        let header = NSTextField(labelWithString: "Diagnostics")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        diagnosticsContainer.addArrangedSubview(header)

        // Fill the info stack's width so messages wrap across the pane.
        diagnosticsContainer.widthAnchor.constraint(
            equalTo: infoStack.widthAnchor, constant: -12).isActive = true

        for diagnostic in diagnostics {
            let (symbol, color): (String, NSColor) = {
                switch diagnostic.severity {
                case .error: return ("xmark.octagon.fill", .systemRed)
                case .warning: return ("exclamationmark.triangle.fill", .systemOrange)
                case .info: return ("info.circle.fill", .secondaryLabelColor)
                }
            }()

            let icon = NSImageView(image: NSImage(
                systemSymbolName: symbol, accessibilityDescription: nil
            ) ?? NSImage())
            icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
            icon.contentTintColor = color
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 14).isActive = true

            let label = NSTextField(wrappingLabelWithString: diagnostic.message)
            label.font = .systemFont(ofSize: 12)
            label.textColor = diagnostic.severity == .info ? .secondaryLabelColor : .labelColor

            let row = NSStackView(views: [icon, label])
            row.orientation = .horizontal
            row.spacing = 6
            row.alignment = .top
            row.widthAnchor.constraint(
                equalTo: diagnosticsContainer.widthAnchor).isActive = true
            label.widthAnchor.constraint(
                equalTo: row.widthAnchor, constant: -20).isActive = true
            diagnosticsContainer.addArrangedSubview(row)
        }
        diagnosticsContainer.isHidden = false
    }

    // MARK: - State tab

    private func buildStateTab() {
        stateOuterStack.orientation = .vertical
        stateOuterStack.alignment = .leading
        stateOuterStack.spacing = 8
        stateOuterStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 16, right: 6)
        stateOuterStack.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSStackView(views: [stateRefreshButton, stateStatusLabel])
        toolbar.orientation = .horizontal
        toolbar.spacing = 10

        stateRefreshButton.bezelStyle = .rounded
        stateRefreshButton.controlSize = .small
        stateRefreshButton.target = self
        stateRefreshButton.action = #selector(refreshStateClicked)

        stateStatusLabel.font = .systemFont(ofSize: 11)
        stateStatusLabel.textColor = .secondaryLabelColor

        stateRowsStack.orientation = .vertical
        stateRowsStack.alignment = .leading
        stateRowsStack.spacing = 8

        stateOuterStack.addArrangedSubview(toolbar)
        stateOuterStack.addArrangedSubview(stateRowsStack)
        embedInScroll(stateScroll, content: stateOuterStack)
    }

    private func showState(_ properties: [String: String]) {
        for view in stateRowsStack.arrangedSubviews {
            stateRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !properties.isEmpty else {
            stateStatusLabel.stringValue = "No state information"
            return
        }
        stateStatusLabel.stringValue = ""
        for key in properties.keys.sorted() {
            let titleLabel = NSTextField(labelWithString: key)
            titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            titleLabel.textColor = .secondaryLabelColor

            let valueLabel = NSTextField(wrappingLabelWithString: properties[key] ?? "")
            valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            valueLabel.textColor = .labelColor

            let row = NSStackView(views: [titleLabel, valueLabel])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 2
            stateRowsStack.addArrangedSubview(row)
        }
    }

    private func refreshState(for job: Job) {
        for view in stateRowsStack.arrangedSubviews {
            stateRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        stateStatusLabel.stringValue = "Loading…"

        guard job.isLoaded else {
            stateStatusLabel.stringValue = "Job is not loaded"
            return
        }

        Task { [weak self] in
            do {
                let output = try await Launchctl.printService(
                    domain: job.domain, label: job.label)
                let properties = ServicePrintParser.properties(output)
                await MainActor.run {
                    guard let self, self.currentJob?.id == job.id else { return }
                    self.showState(properties)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.currentJob?.id == job.id else { return }
                    self.stateRowsStack.arrangedSubviews.forEach {
                        self.stateRowsStack.removeArrangedSubview($0)
                        $0.removeFromSuperview()
                    }
                    self.stateStatusLabel.stringValue = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func refreshStateClicked() {
        guard let job = currentJob else { return }
        refreshState(for: job)
    }

    // MARK: - Logs tab

    private func buildLogsTab() {
        logSourcePopup.addItems(withTitles: ["Standard Output", "Standard Error"])
        logSourcePopup.target = self
        logSourcePopup.action = #selector(logSourceChanged)
        logSourcePopup.font = .systemFont(ofSize: 12)

        logStatusLabel.font = .systemFont(ofSize: 11)
        logStatusLabel.textColor = .secondaryLabelColor
        logStatusLabel.lineBreakMode = .byTruncatingMiddle

        let bar = NSStackView(views: [logSourcePopup, logStatusLabel])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        bar.translatesAutoresizingMaskIntoConstraints = false

        configureTextView(logTextView)
        logScroll.documentView = logTextView
        logScroll.hasVerticalScroller = true
        logScroll.autohidesScrollers = true
        logScroll.borderType = .noBorder
        logScroll.translatesAutoresizingMaskIntoConstraints = false

        logsContainer.addSubview(bar)
        logsContainer.addSubview(logScroll)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: logsContainer.topAnchor),
            bar.leadingAnchor.constraint(equalTo: logsContainer.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: logsContainer.trailingAnchor),
            logScroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            logScroll.leadingAnchor.constraint(equalTo: logsContainer.leadingAnchor),
            logScroll.trailingAnchor.constraint(equalTo: logsContainer.trailingAnchor),
            logScroll.bottomAnchor.constraint(equalTo: logsContainer.bottomAnchor),
        ])
    }

    private func configureTextView(_ textView: NSTextView) {
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
    }

    private func configureScroll(_ scrollView: NSScrollView, document: NSView) {
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
    }

    /// Uses `content` directly as the scroll document, constrained to be at
    /// least as tall as the clip view so short content top-aligns.
    private func embedInScroll(_ scrollView: NSScrollView, content: NSView) {
        scrollView.documentView = content
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        NSLayoutConstraint.activate([
            content.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    @objc private func logSourceChanged() {
        refreshLogs()
    }

    private func logPath(for job: Job) -> String? {
        let key = logSourcePopup.indexOfSelectedItem == 0
            ? "StandardOutPath" : "StandardErrorPath"
        guard let path = job.plist?[key] as? String, !path.isEmpty, path != "/dev/null" else {
            return nil
        }
        return path
    }

    private func refreshLogsIfNeeded() {
        guard selectedTab == .logs, currentJob != nil else { return }
        refreshLogs()
    }

    private func refreshLogs() {
        guard let job = currentJob else { return }
        guard let path = logPath(for: job) else {
            logTextView.string = ""
            logStatusLabel.stringValue = "No log file configured"
            return
        }
        guard let text = LogTail.tail(path: path) else {
            logTextView.string = ""
            logStatusLabel.stringValue = "Cannot read \(path)"
            return
        }
        logTextView.string = text
        logStatusLabel.stringValue = path
        // Follow the tail.
        let end = NSRange(location: (text as NSString).length, length: 0)
        logTextView.setSelectedRange(end)
        logTextView.scrollRangeToVisible(end)
    }

    // MARK: - XML tab

    private func buildXMLTab() {
        configureTextView(xmlTextView)
        xmlTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        configureScroll(xmlScroll, document: xmlTextView)
    }

    private func showXML(for job: Job) {
        guard let plist = job.plist ?? job.plistPath.flatMap({ Plist.load(URL(fileURLWithPath: $0)) }),
              let data = try? PropertyListSerialization.data(
                  fromPropertyList: plist, format: .xml, options: 0),
              let text = String(data: data, encoding: .utf8) else {
            xmlTextView.string = job.plistPath.map { "Cannot read \($0)" } ?? "No plist"
            return
        }
        xmlTextView.string = text
    }

    // MARK: - Tabs & selection

    @objc private func tabChanged() {
        selectedTab = Tab(rawValue: segmented.selectedSegment) ?? .info
        applyTabVisibility()
        switch selectedTab {
        case .state:
            if let job = currentJob { refreshState(for: job) }
        case .logs:
            refreshLogs()
        case .info, .xml:
            break
        }
    }

    private func applyTabVisibility() {
        infoScroll.isHidden = selectedTab != .info
        stateScroll.isHidden = selectedTab != .state
        logsContainer.isHidden = selectedTab != .logs
        xmlScroll.isHidden = selectedTab != .xml
    }

    @objc private func editClicked() {
        guard let job = currentJob, job.plistPath != nil else { return }
        onEdit?(job)
    }

    func show(job: Job?) {
        currentJob = job
        editButton.isEnabled = job?.plistPath != nil
        guard let job else {
            for (_, label) in valueLabels { label.stringValue = "—" }
            rebuildDiagnostics(for: nil)
            stateRowsStack.arrangedSubviews.forEach {
                stateRowsStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            stateStatusLabel.stringValue = ""
            logTextView.string = ""
            logStatusLabel.stringValue = ""
            xmlTextView.string = ""
            return
        }

        valueLabels["label"]?.stringValue = job.label
        valueLabels["domain"]?.stringValue = job.domain.rawValue
        valueLabels["state"]?.stringValue = stateText(for: job)
        valueLabels["pid"]?.stringValue = job.pid.map(String.init) ?? "—"
        valueLabels["exitStatus"]?.stringValue = job.lastExitStatus.map(String.init) ?? "—"
        valueLabels["path"]?.stringValue = job.plistPath ?? "—"

        rebuildDiagnostics(for: job)
        showXML(for: job)

        if selectedTab == .state {
            refreshState(for: job)
        }
        if selectedTab == .logs {
            refreshLogs()
        }
    }

    private func stateText(for job: Job) -> String {
        if job.pid != nil { return "Running" }
        if job.isDisabled { return "Disabled" }
        if job.isLoaded { return "Loaded" }
        return "Not loaded"
    }
}
