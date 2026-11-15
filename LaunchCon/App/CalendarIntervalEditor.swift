import AppKit

/// Editor for `StartCalendarInterval`-style values: a dict or array of dicts
/// with integer keys Second/Minute/Hour/Day/Month/Weekday.
///
/// Each schedule is a small two-line block of key/value fields. Empty fields
/// mean the key is absent. One schedule writes back as a dict; multiple as an
/// array of dicts.
final class CalendarIntervalEditor: NSView {

    var onChange: (() -> Void)?

    private let stack = NSStackView()
    private var scheduleViews: [ScheduleView] = []
    private let addButton = NSButton(title: "+ Add Schedule", target: nil, action: nil)

    /// nil when every field is empty or the value shape was unexpected.
    var plistValue: Any? {
        let schedules = scheduleViews.compactMap { $0.schedule }
        if schedules.isEmpty { return nil }
        if schedules.count == 1 { return schedules[0] }
        return schedules
    }

    var hasInvalidInput: Bool {
        scheduleViews.contains { !$0.isValid }
    }

    init(value: Any?) {
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addScheduleClicked)
        stack.addArrangedSubview(addButton)

        // Seed from existing value: single dict or array of dicts.
        if let dict = value as? [String: Any] {
            addSchedule(dict)
        } else if let array = value as? [Any] {
            for case let dict as [String: Any] in array {
                addSchedule(dict)
            }
        }
        if scheduleViews.isEmpty {
            addSchedule([:])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addSchedule(_ dict: [String: Any]) {
        let view = ScheduleView(schedule: dict)
        view.onChange = { [weak self] in self?.onChange?() }
        view.onRemove = { [weak self, weak view] in
            guard let self, let view else { return }
            self.scheduleViews.removeAll { $0 === view }
            self.stack.removeArrangedSubview(view)
            view.removeFromSuperview()
            self.onChange?()
        }
        scheduleViews.append(view)
        // Insert before the Add button.
        stack.insertArrangedSubview(view, at: stack.arrangedSubviews.count - 1)
    }

    @objc private func addScheduleClicked() {
        addSchedule([:])
        onChange?()
    }
}

/// One schedule: two rows of labeled integer fields plus a Remove button.
private final class ScheduleView: NSView {

    var onChange: (() -> Void)?
    var onRemove: (() -> Void)?

    private var fields: [String: NSTextField] = [:]

    private static let firstRowKeys = ["Hour", "Minute", "Second"]
    private static let secondRowKeys = ["Day", "Month", "Weekday"]

    /// The schedule as [String: Int], or nil if every field is empty.
    var schedule: [String: Int]? {
        guard isValid else { return nil }
        var result: [String: Int] = [:]
        for (key, field) in fields {
            let s = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, let int = Int(s) else { continue }
            result[key] = int
        }
        return result.isEmpty ? nil : result
    }

    /// False when a non-empty field isn't an integer.
    var isValid: Bool {
        fields.values.allSatisfy { field in
            let s = field.stringValue.trimmingCharacters(in: .whitespaces)
            return s.isEmpty || Int(s) != nil
        }
    }

    init(schedule: [String: Any]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        var mutableFields: [String: NSTextField] = [:]
        container.addArrangedSubview(makeFieldRow(Self.firstRowKeys, schedule: schedule, fields: &mutableFields))

        let secondRow = NSStackView()
        secondRow.orientation = .horizontal
        secondRow.spacing = 8
        secondRow.alignment = .centerY
        secondRow.addArrangedSubview(makeFieldRow(Self.secondRowKeys, schedule: schedule, fields: &mutableFields))

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeClicked))
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .small
        secondRow.addArrangedSubview(removeButton)
        secondRow.addArrangedSubview(NSView()) // spacer
        container.addArrangedSubview(secondRow)

        fields = mutableFields
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeFieldRow(_ keys: [String], schedule: [String: Any], fields: inout [String: NSTextField]) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        for key in keys {
            let label = NSTextField(labelWithString: key)
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            label.widthAnchor.constraint(equalToConstant: 42).isActive = true

            let field = NSTextField(string: intString(schedule[key]))
            field.font = .systemFont(ofSize: 12)
            field.placeholderString = "–"
            field.widthAnchor.constraint(equalToConstant: 44).isActive = true
            field.target = self
            field.action = #selector(fieldEdited)
            fields[key] = field

            row.addArrangedSubview(label)
            row.addArrangedSubview(field)
        }
        return row
    }

    private func intString(_ value: Any?) -> String {
        (value as? NSNumber)?.stringValue ?? ""
    }

    @objc private func fieldEdited() {
        onChange?()
    }

    @objc private func removeClicked() {
        onRemove?()
    }
}
