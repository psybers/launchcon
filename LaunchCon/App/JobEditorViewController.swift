import AppKit

/// Flipped document container so the scroll view's initial clip origin
/// (0, 0) is the TOP of the document, not the bottom.
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Schema-driven editor for a launchd plist. Each supported key gets a row
/// with an appropriate control; unknown/complex keys are preserved on save.
final class JobEditorViewController: NSViewController {

    let document: PlistDocument
    var onSaved: (() -> Void)?

    private let scrollView = NSScrollView()
    private let formStack = NSStackView()
    private var controls: [String: NSControl] = [:]
    private var textViews: [String: NSTextView] = [:]
    private var calendarEditors: [String: CalendarIntervalEditor] = [:]
    private var keyPalettePopover: NSPopover?
    private var statusLabel: NSTextField!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!
    /// Called when the user cancels (button or Escape).
    var onCancel: (() -> Void)?

    init(document: PlistDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View setup

    override func loadView() {
        let container = NSView()

        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 10
        formStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        formStack.translatesAutoresizingMaskIntoConstraints = false

        // Wrap the form in a container pinned to the top of the scroll view.
        // The container is at least as tall as the clip view, so a short form
        // top-aligns instead of bottom-aligning (NSScrollView default).
        let documentContainer = FlippedDocumentView()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        formStack.setContentHuggingPriority(.required, for: .vertical)
        documentContainer.addSubview(formStack)
        scrollView.documentView = documentContainer
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let pathLabel = NSTextField(labelWithString: document.url.path)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        cancelButton.target = self

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let bottomBar = NSStackView(views: [saveButton, cancelButton, statusLabel])
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 12
        bottomBar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 12, right: 16)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        let keysButton = NSButton(title: "Keys…", target: self, action: #selector(showKeyPalette(_:)))
        keysButton.bezelStyle = .rounded
        keysButton.controlSize = .small

        let headerRow = NSStackView(views: [pathLabel, NSView(), keysButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        let headerStack = NSStackView(views: [headerRow])
        headerStack.orientation = .vertical
        headerStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 4, right: 16)
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(headerStack)
        container.addSubview(scrollView)
        container.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: container.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            formStack.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            formStack.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            formStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            documentContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            documentContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        // Container tracks the form's height but never shrinks below the clip
        // view, so short forms top-align and tall forms scroll.
        let heightMatch = documentContainer.heightAnchor.constraint(equalTo: formStack.heightAnchor)
        heightMatch.priority = .defaultHigh
        heightMatch.isActive = true

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildRows()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Document is flipped, so .zero is the top-left.
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Scrolls the row for `key` into view and flashes it briefly. Used when
    /// jumping here from a diagnostic in the detail pane.
    func highlight(key: String) {
        guard let index = JobKeySchema.all.firstIndex(where: { $0.key == key }),
              index < formStack.arrangedSubviews.count else { return }
        let row = formStack.arrangedSubviews[index]
        view.layoutSubtreeIfNeeded()

        // Document is flipped: y grows downward from the top.
        let rowRect = row.convert(row.bounds, to: scrollView.documentView)
        let target = CGPoint(x: 0, y: max(0, rowRect.minY - 60))
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        flash(row)
        if let textView = textViews[key] {
            view.window?.makeFirstResponder(textView)
        }
    }

    private func flash(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.cornerRadius = 6
        let tint = NSColor.systemYellow.withAlphaComponent(0.4).cgColor
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = tint
        anim.toValue = NSColor.clear.cgColor
        anim.duration = 1.2
        layer.add(anim, forKey: "diagnosticFlash")
    }

    // MARK: - Row construction

    private func effectiveKind(for schema: JobKeySchema) -> PlistEditorKind {
        let value = document.value(forKey: schema.key)
        switch schema.kind {
        case .bool:
            // KeepAlive may be a dictionary — not editable as a checkbox.
            // Non-boolean scalars (e.g. KeepAlive = 1) aren't either.
            if value is [String: Any] { return .unsupported }
            if let number = value as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID() {
                return .unsupported
            }
            return .bool
        case .integer:
            if let number = value as? NSNumber,
               CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .unsupported
            }
            return value == nil || value is NSNumber ? .integer : .unsupported
        case .string, .userName, .groupName:
            return value == nil || value is String ? schema.kind : .unsupported
        case .stringList:
            return value == nil || value is [String] ? .stringList : .unsupported
        case .stringMap:
            return value == nil || value is [String: String] ? .stringMap : .unsupported
        case .calendarInterval:
            return isCalendarIntervalValue(value) ? .calendarInterval : .unsupported
        default:
            return schema.kind
        }
    }

    /// Accepts nil, a dict of numbers, or an array of dicts of numbers.
    private func isCalendarIntervalValue(_ value: Any?) -> Bool {
        if value == nil { return true }
        if let dict = value as? [String: Any] {
            return dict.values.allSatisfy { $0 is NSNumber }
        }
        if let array = value as? [Any] {
            return array.allSatisfy {
                ($0 as? [String: Any])?.values.allSatisfy { $0 is NSNumber } ?? false
            }
        }
        return false
    }

    private func rebuildRows() {
        for view in formStack.arrangedSubviews {
            formStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        controls.removeAll()
        textViews.removeAll()
        calendarEditors.removeAll()
        for schema in JobKeySchema.all {
            formStack.addArrangedSubview(makeRow(for: schema))
        }
    }

    // MARK: - Key palette

    /// Opens the searchable key palette; clicking a key adds it to the
    /// document (with its schema default when unset) and highlights its row.
    @objc private func showKeyPalette(_ sender: NSButton) {
        if let popover = keyPalettePopover, popover.isShown {
            popover.close()
            keyPalettePopover = nil
            return
        }
        let palette = KeyPaletteViewController(document: document)
        palette.onPick = { [weak self] key in
            self?.addKey(key)
            (self?.keyPalettePopover?.contentViewController as? KeyPaletteViewController)?
                .reload()
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 700, height: 340)
        popover.contentViewController = palette
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        keyPalettePopover = popover
    }

    /// Inserts `key` into the document when absent (using the schema's
    /// default value, if any), rebuilds the form, and scrolls to the row.
    func addKey(_ key: String) {
        guard let schema = JobKeySchema.all.first(where: { $0.key == key }) else { return }
        if document.value(forKey: key) == nil, let defaultValue = schema.defaultValue {
            document.set(defaultValue, forKey: key)
            rebuildRows()
        }
        edited()
        highlight(key: key)
    }

    private func makeRow(for schema: JobKeySchema) -> NSView {
        let titleLabel = NSTextField(labelWithString: schema.title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .right
        titleLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let kind = effectiveKind(for: schema)
        let control = makeControl(for: schema, kind: kind)

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func makeControl(for schema: JobKeySchema, kind: PlistEditorKind) -> NSView {
        let value = document.value(forKey: schema.key)

        switch kind {
        case .string:
            let field = NSTextField(string: stringValue(value))
            field.placeholderString = "(not set)"
            field.font = .systemFont(ofSize: 13)
            wire(field)
            controls[schema.key] = field

            guard schema.isPath else { return field }
            let stack = NSStackView(views: [field, makeChooseButton()])
            stack.orientation = .horizontal
            stack.spacing = 6
            return stack

        case .popup(let options):
            return makePopup(options: options, current: value as? String, key: schema.key)

        case .userName:
            return makePopup(options: SystemAccounts.userNames, current: value as? String, key: schema.key)

        case .groupName:
            return makePopup(options: SystemAccounts.groupNames, current: value as? String, key: schema.key)

        case .bool:
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(edited))
            checkbox.state = (value as? Bool) == true ? .on : .off
            controls[schema.key] = checkbox
            return checkbox

        case .integer:
            let field = NSTextField(string: intValue(value))
            field.placeholderString = "(not set)"
            field.font = .systemFont(ofSize: 13)
            field.widthAnchor.constraint(equalToConstant: 120).isActive = true
            wire(field)
            controls[schema.key] = field
            return field

        case .stringList:
            let text = (value as? [String])?.joined(separator: "\n") ?? ""
            return makeTextEditor(key: schema.key, text: text,
                                  placeholder: "One argument per line")

        case .stringMap:
            let dict = value as? [String: String] ?? [:]
            let text = dict.keys.sorted().map { "\($0)=\(dict[$0] ?? "")" }.joined(separator: "\n")
            return makeTextEditor(key: schema.key, text: text,
                                  placeholder: "KEY=VALUE, one per line")

        case .calendarInterval:
            let editor = CalendarIntervalEditor(value: value)
            editor.onChange = { [weak self] in self?.edited() }
            calendarEditors[schema.key] = editor
            return editor

        case .unsupported:
            let field = NSTextField(labelWithString: describe(value))
            field.textColor = .secondaryLabelColor
            field.font = .systemFont(ofSize: 12)
            return field
        }
    }

    /// Popup whose first item is blank (unset); an existing value that isn't
    /// in `options` is appended so it round-trips.
    private func makePopup(options: [String], current: String?, key: String) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        var allOptions = options
        if let current, !options.contains(current) {
            allOptions.append(current)
        }
        popup.addItems(withTitles: [""] + allOptions)
        if let current, let index = allOptions.firstIndex(of: current) {
            popup.selectItem(at: index + 1)
        }
        popup.target = self
        popup.action = #selector(edited)
        popup.font = .systemFont(ofSize: 13)
        controls[key] = popup
        return popup
    }

    private func wire(_ field: NSTextField) {
        field.target = self
        field.action = #selector(edited)
    }

    private func makeChooseButton() -> NSButton {
        let button = NSButton(title: "Choose…", target: self, action: #selector(choosePath(_:)))
        button.bezelStyle = .rounded
        return button
    }

    @objc private func choosePath(_ sender: NSButton) {
        // The button sits beside its text field in a horizontal stack.
        guard let stack = sender.superview as? NSStackView,
              let field = stack.arrangedSubviews.first as? NSTextField else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        field.stringValue = url.path
        edited()
    }

    private func makeTextEditor(key: String, text: String, placeholder: String) -> NSView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        textViews[key] = textView
        return scroll
    }

    // MARK: - Value helpers

    private func stringValue(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private func intValue(_ value: Any?) -> String {
        (value as? NSNumber)?.stringValue ?? ""
    }

    private func describe(_ value: Any?) -> String {
        guard let value else { return "(complex value)" }
        switch value {
        case is [String: Any]: return "(dictionary)"
        case is [Any]: return "(array)"
        case is String: return value as! String
        default: return "\(value)"
        }
    }

    // MARK: - Save

    /// True when the current control values differ from the saved plist.
    var isDirty: Bool {
        document.hasChanges(comparedTo: buildEditedContents().contents)
    }

    /// Builds the plist dictionary the controls currently represent,
    /// plus validation errors for fields that can't be represented.
    private func buildEditedContents() -> (contents: [String: Any], integerError: String?, calendarError: String?) {
        var newContents = document.contents
        var integerError: String?
        var calendarError: String?

        for schema in JobKeySchema.all {
            let kind = effectiveKind(for: schema)
            let key = schema.key

            switch kind {
            case .string:
                guard let field = controls[key] as? NSTextField else { continue }
                let s = field.stringValue.trimmingCharacters(in: .whitespaces)
                if s.isEmpty { newContents.removeValue(forKey: key) } else { newContents[key] = s }

            case .bool:
                guard let checkbox = controls[key] as? NSButton else { continue }
                if checkbox.state == .on {
                    newContents[key] = true
                } else if document.savedContents[key] != nil {
                    // Preserve an explicit `false`; don't invent keys that were absent.
                    newContents[key] = false
                } else {
                    newContents.removeValue(forKey: key)
                }

            case .integer:
                guard let field = controls[key] as? NSTextField else { continue }
                let s = field.stringValue.trimmingCharacters(in: .whitespaces)
                if s.isEmpty {
                    newContents.removeValue(forKey: key)
                } else if let int = Int(s) {
                    newContents[key] = int
                } else {
                    integerError = schema.title
                }

            case .popup, .userName, .groupName:
                guard let popup = controls[key] as? NSPopUpButton else { continue }
                let title = popup.titleOfSelectedItem ?? ""
                if title.isEmpty { newContents.removeValue(forKey: key) } else { newContents[key] = title }

            case .stringList:
                guard let tv = textViews[key] else { continue }
                let args = tv.string
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if args.isEmpty { newContents.removeValue(forKey: key) } else { newContents[key] = args }

            case .stringMap:
                guard let tv = textViews[key] else { continue }
                var map: [String: String] = [:]
                for line in tv.string.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, let eq = trimmed.firstIndex(of: "=") else { continue }
                    let k = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                    let v = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    if !k.isEmpty { map[k] = v }
                }
                if map.isEmpty { newContents.removeValue(forKey: key) } else { newContents[key] = map }

            case .calendarInterval:
                guard let editor = calendarEditors[key] else { continue }
                if editor.hasInvalidInput {
                    calendarError = schema.title
                    continue
                }
                if let plistValue = editor.plistValue {
                    newContents[key] = plistValue
                } else {
                    newContents.removeValue(forKey: key)
                }

            case .unsupported:
                continue // preserve existing value untouched
            }
        }

        return (newContents, integerError, calendarError)
    }

    /// Clears the "Saved" status after any edit.
    @objc private func edited() {
        statusLabel?.stringValue = ""
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    /// Saves the document. Returns false if validation fails or the write errors.
    @discardableResult
    @objc func save() -> Bool {
        let (newContents, integerError, calendarError) = buildEditedContents()

        if integerError != nil || calendarError != nil {
            let alert = NSAlert()
            alert.messageText = "Invalid value"
            if let integerError {
                alert.informativeText = "\(integerError) must be an integer."
            } else {
                alert.informativeText = "\(calendarError!) contains a non-integer value."
            }
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }

        do {
            try document.save(newContents)
            statusLabel.stringValue = "Saved"
            onSaved?()
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Save failed"
            alert.informativeText = "\(error)"
            alert.alertStyle = .critical
            alert.runModal()
            return false
        }
    }
}

extension JobEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        edited()
    }
}
