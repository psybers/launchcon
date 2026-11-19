import AppKit

/// Window hosting the plist editor for one job.
final class JobEditorWindowController: NSWindowController, NSWindowDelegate {

    private let editor: JobEditorViewController
    private var escapeMonitor: Any?
    private var isCanceling = false
    var onClose: (() -> Void)?

    var plistDocument: PlistDocument { editor.document }

    init(document: PlistDocument, jobLabel: String, onSaved: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit \(jobLabel)"

        editor = JobEditorViewController(document: document)
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 620, height: 680))
        window.center()

        super.init(window: window)
        window.delegate = self

        editor.onSaved = { [weak self] in
            onSaved()
            // save() updated the dirty baseline, so this closes without
            // the unsaved-changes prompt.
            self?.window?.close()
        }
        editor.onCancel = { [weak self] in
            self?.cancel()
        }

        // Escape cancels from anywhere in the window, including text fields.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 53 else {
                return event
            }
            self.cancel()
            return nil
        }
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Scrolls to and flashes the editor row for `key`.
    func highlight(key: String) {
        editor.view.layoutSubtreeIfNeeded()
        editor.highlight(key: key)
    }

    /// Closes the window, prompting to save first if there are unsaved changes.
    func cancel() {
        guard confirmClose() else { return }
        isCanceling = true
        window?.close()
    }

    /// Returns true if the window may close; prompts when dirty.
    private func confirmClose() -> Bool {
        guard editor.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(editor.document.url.lastPathComponent)?"
        alert.informativeText = "You have unsaved changes."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return editor.save()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        isCanceling || confirmClose()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
