import AppKit
import GlanceCore

/// Create / edit form, shown in a themed popover panel beside the calendar.
@MainActor
final class EventEditorController: NSViewController, NSTextFieldDelegate {
    enum Result { case saved, deleted, cancelled }

    static let labelWidth: CGFloat = 62
    static let fieldWidth: CGFloat = 248
    static let inset: CGFloat = 16
    static let spacing: CGFloat = 8

    private var draft: EventDraft
    private let calendars: [CalendarSourceGroup]
    private let editable: Bool
    private let calendar: Calendar
    private let colors: ThemeColors

    /// Persist the draft. Throwing shows the error and keeps the editor open.
    var save: ((EventDraft, _ futureEvents: Bool) async throws -> Void)?
    var delete: ((EventDraft, _ futureEvents: Bool) async throws -> Void)?
    var finish: ((Result) -> Void)?

    private lazy var titleField = themedTextField(placeholder: "New Event", colors: colors,
                                                  font: .systemFont(ofSize: 14, weight: .semibold))
    private let allDay = ThemedCheckbox(title: "All-day")
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let calendarPopup = NSPopUpButton()
    private lazy var locationField = themedTextField(placeholder: "Location or video call", colors: colors)
    private lazy var urlField = themedTextField(placeholder: "https://", colors: colors)
    private let notesView = NSTextView()
    private lazy var saveButton = ThemedButton(title: "Save", kind: .primary, target: self, action: #selector(saveClicked))
    private lazy var cancelButton = ThemedButton(title: "Cancel", kind: .secondary, target: self, action: #selector(cancelClicked))
    private lazy var deleteButton = ThemedButton(title: "Delete…", kind: .destructive, target: self, action: #selector(deleteClicked))
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var boxes: [ThemedFieldBox] = []
    private var focusObservation: NSKeyValueObservation?

    init(draft: EventDraft, calendars: [CalendarSourceGroup], editable: Bool, calendar: Calendar, colors: ThemeColors) {
        self.draft = draft
        self.calendars = calendars
        self.editable = editable
        self.calendar = calendar
        self.colors = colors
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func box(_ v: NSView, height: CGFloat? = 26, insets: NSEdgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)) -> ThemedFieldBox {
        let b = ThemedFieldBox(v, insets: insets, height: height)
        b.colors = colors
        b.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true
        boxes.append(b)
        return b
    }

    override func loadView() {
        let c = colors
        titleField.stringValue = draft.title
        titleField.delegate = self
        locationField.stringValue = draft.location
        locationField.delegate = self
        urlField.stringValue = draft.urlText
        urlField.delegate = self

        allDay.isOn = draft.isAllDay
        allDay.colors = c
        allDay.target = self
        allDay.action = #selector(allDayChanged)

        for p in [startPicker, endPicker] {
            p.datePickerStyle = .textField
            p.isBezeled = false
            p.isBordered = false
            p.drawsBackground = false
            p.focusRingType = .none
            p.textColor = c.primaryText
            p.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            p.calendar = calendar
            p.timeZone = calendar.timeZone
            p.target = self
            p.action = #selector(datesChanged(_:))
        }
        startPicker.dateValue = draft.start
        endPicker.dateValue = draft.isAllDay ? draft.end.addingTimeInterval(-1) : draft.end
        updatePickerElements()

        buildCalendarMenu()
        calendarPopup.isBordered = false
        calendarPopup.focusRingType = .none
        calendarPopup.font = .systemFont(ofSize: 13)
        calendarPopup.contentTintColor = c.primaryText

        notesView.string = draft.notes
        notesView.font = .systemFont(ofSize: 13)
        notesView.isRichText = false
        notesView.allowsUndo = true
        notesView.textContainerInset = NSSize(width: 0, height: 2)
        notesView.textContainer?.lineFragmentPadding = 0
        style(textView: notesView, c)
        let notesScroll = NSScrollView()
        notesScroll.documentView = notesView
        notesScroll.hasVerticalScroller = true
        notesScroll.autohidesScrollers = true
        notesScroll.scrollerStyle = .overlay
        notesScroll.drawsBackground = false
        notesScroll.borderType = .noBorder
        notesView.autoresizingMask = [.width]
        notesView.isVerticallyResizable = true
        notesView.textContainer?.widthTracksTextView = true

        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.alignment = .right
            l.font = .systemFont(ofSize: 13)
            l.textColor = c.secondaryText
            return l
        }
        let grid = NSGridView(views: [
            [label("Title"), box(titleField, height: 30, insets: NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8))],
            [NSGridCell.emptyContentView, allDay],
            [label("Starts"), box(startPicker)],
            [label("Ends"), box(endPicker)],
            [label("Calendar"), box(calendarPopup, insets: NSEdgeInsets(top: 1, left: 2, bottom: 1, right: 2))],
            [label("Location"), box(locationField)],
            [label("URL"), box(urlField)],
            [label("Notes"), box(notesScroll, height: 72, insets: NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 4))],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = Self.labelWidth
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        grid.row(at: 7).rowAlignment = .none
        grid.row(at: 7).yPlacement = .top
        grid.cell(atColumnIndex: 0, rowIndex: 7).yPlacement = .top
        grid.columnSpacing = Self.spacing
        grid.rowSpacing = Self.spacing
        notesLabelTopInset(grid)

        errorLabel.textColor = c.destructive
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.isHidden = true
        errorLabel.preferredMaxLayoutWidth = Self.fieldWidth

        saveButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        deleteButton.keyEquivalent = "\u{8}"
        deleteButton.keyEquivalentModifierMask = .command
        deleteButton.keyEquivalentSkipsTextEditing = true
        for b in [saveButton, cancelButton, deleteButton] { b.colors = c }
        deleteButton.isHidden = draft.isNew || !editable
        if !editable {
            saveButton.isHidden = true
            cancelButton.title = "Close"
            cancelButton.colors = c
            cancelButton.keyEquivalent = "\r"
            [titleField, locationField, urlField].forEach { $0.isEditable = false }
            [allDay, startPicker, endPicker, calendarPopup].forEach { $0.isEnabled = false }
            notesView.isEditable = false
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [deleteButton, spacer, cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = Self.spacing
        // The error sits under the fields, aligned with them.
        let errorRow = NSStackView(views: [errorLabel])
        errorRow.edgeInsets = NSEdgeInsets(top: 0, left: Self.labelWidth + Self.spacing, bottom: 0, right: 0)
        let stack = NSStackView(views: [grid, errorRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(Self.spacing, after: grid)
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        stack.appearance = c.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        view = stack
    }

    /// Line the Notes label up with the first line of text in its box.
    private func notesLabelTopInset(_ grid: NSGridView) {
        grid.cell(atColumnIndex: 0, rowIndex: 7).customPlacementConstraints = []
        if let label = grid.cell(atColumnIndex: 0, rowIndex: 7).contentView,
           let box = grid.cell(atColumnIndex: 1, rowIndex: 7).contentView {
            let font = notesView.font ?? .systemFont(ofSize: 13)
            grid.cell(atColumnIndex: 0, rowIndex: 7).customPlacementConstraints = [
                label.firstBaselineAnchor.constraint(equalTo: box.topAnchor, constant: 5 + 2 + ceil(font.ascender)),
            ]
        }
    }

    /// Call once the view is in its window: tracks focus for the accent ring.
    func didPresent() {
        if let window = view.window {
            focusObservation = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
                MainActor.assumeIsolated { self?.updateFocus(window.firstResponder) }
            }
        }
        if editable { view.window?.makeFirstResponder(titleField) }
    }

    func willClose() { focusObservation = nil }

    private func updateFocus(_ responder: NSResponder?) {
        let v = responder as? NSView
        for b in boxes { b.focused = v.map { $0 === b || $0.isDescendant(of: b) } ?? false }
    }

    private func buildCalendarMenu() {
        let menu = NSMenu()
        var selected: NSMenuItem?
        for group in calendars {
            let header = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(header)
            for c in group.calendars where c.allowsModifications || c.id == draft.calendarID {
                let item = NSMenuItem(title: c.title, action: nil, keyEquivalent: "")
                item.representedObject = c.id
                item.image = Self.dot(NSColor(rgba: c.color))
                item.indentationLevel = 1
                menu.addItem(item)
                if c.id == draft.calendarID { selected = item }
            }
        }
        menu.autoenablesItems = false
        calendarPopup.menu = menu
        if let selected { calendarPopup.select(selected) }
        else if let first = menu.items.first(where: { $0.representedObject != nil }) { calendarPopup.select(first) }
    }

    /// The calendar's colour dot, as in the agenda.
    static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private func updatePickerElements() {
        let elements: NSDatePicker.ElementFlags = allDay.isOn ? [.yearMonthDay] : [.yearMonthDay, .hourMinute]
        startPicker.datePickerElements = elements
        endPicker.datePickerElements = elements
    }

    @objc private func allDayChanged() { updatePickerElements() }

    @objc private func datesChanged(_ sender: NSDatePicker) {
        // Moving the start keeps the duration, like Calendar.app.
        if sender === startPicker {
            let duration = max(0, draft.end.timeIntervalSince(draft.start))
            draft.start = startPicker.dateValue
            draft.end = draft.start.addingTimeInterval(duration)
            endPicker.dateValue = draft.end
        } else {
            draft.end = endPicker.dateValue
        }
        hideError()
    }

    private func collect() -> EventDraft {
        var d = draft
        d.title = titleField.stringValue
        d.isAllDay = allDay.isOn
        d.start = startPicker.dateValue
        d.end = endPicker.dateValue
        d.calendarID = calendarPopup.selectedItem?.representedObject as? String
        d.location = locationField.stringValue
        d.urlText = urlField.stringValue
        d.notes = notesView.string
        return d
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    private func hideError() { errorLabel.isHidden = true }

    func controlTextDidChange(_ obj: Notification) { hideError() }

    /// Ask whether a change to a recurring event applies to future events. Nil = cancelled.
    private func askSpan(verb: String) -> Bool? {
        let alert = NSAlert()
        alert.messageText = "\(verb) a repeating event"
        alert.informativeText = "Do you want to \(verb.lowercased()) only this occurrence, or this and all future occurrences?"
        alert.addButton(withTitle: "Only This Event")
        alert.addButton(withTitle: "All Future Events")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    @objc private func saveClicked() {
        let d = collect()
        if let error = d.validate(calendar: calendar) {
            showError(error.errorDescription ?? "This event can’t be saved.")
            return
        }
        var future = false
        if !d.isNew && d.isRecurring {
            guard let f = askSpan(verb: "Change") else { return }
            future = f
        }
        saveButton.isEnabled = false
        Task {
            do {
                try await save?(d, future)
                finish?(.saved)
            } catch {
                saveButton.isEnabled = true
                showError("Couldn’t save the event: \(error.localizedDescription)")
            }
        }
    }

    @objc func cancelClicked() { finish?(.cancelled) }

    @objc func deleteClicked() {
        let d = collect()
        var future = false
        if d.isRecurring {
            guard let f = askSpan(verb: "Delete") else { return }
            future = f
        } else {
            let alert = NSAlert()
            alert.messageText = "Delete “\(draft.trimmedTitle)”?"
            alert.informativeText = "This removes the event from the calendar on all your devices."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            do {
                try await delete?(d, future)
                finish?(.deleted)
            } catch {
                showError("Couldn’t delete the event: \(error.localizedDescription)")
            }
        }
    }
}
