import AppKit
import GlanceCore

/// Create / edit form shown in an NSPopover.
@MainActor
final class EventEditorController: NSViewController, NSTextFieldDelegate {
    enum Result { case saved, deleted, cancelled }

    private var draft: EventDraft
    private let calendars: [CalendarSourceGroup]
    private let editable: Bool
    private let calendar: Calendar

    /// Persist the draft. Throwing shows the error and keeps the editor open.
    var save: ((EventDraft, _ futureEvents: Bool) async throws -> Void)?
    var delete: ((EventDraft, _ futureEvents: Bool) async throws -> Void)?
    var finish: ((Result) -> Void)?

    private let titleField = NSTextField()
    private let allDay = NSButton(checkboxWithTitle: "All-day", target: nil, action: nil)
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let calendarPopup = NSPopUpButton()
    private let locationField = NSTextField()
    private let urlField = NSTextField()
    private let notesView = NSTextView()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete…", target: nil, action: nil)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(draft: EventDraft, calendars: [CalendarSourceGroup], editable: Bool, calendar: Calendar) {
        self.draft = draft
        self.calendars = calendars
        self.editable = editable
        self.calendar = calendar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        titleField.placeholderString = "New Event"
        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.stringValue = draft.title
        titleField.delegate = self

        allDay.state = draft.isAllDay ? .on : .off
        allDay.target = self
        allDay.action = #selector(allDayChanged)

        for p in [startPicker, endPicker] {
            p.datePickerStyle = .textFieldAndStepper
            p.isBezeled = true
            p.calendar = calendar
            p.timeZone = calendar.timeZone
            p.target = self
            p.action = #selector(datesChanged(_:))
        }
        startPicker.dateValue = draft.start
        endPicker.dateValue = draft.isAllDay ? draft.end.addingTimeInterval(-1) : draft.end
        updatePickerElements()

        buildCalendarMenu()
        locationField.placeholderString = "Location or video call"
        locationField.stringValue = draft.location
        urlField.placeholderString = "https://"
        urlField.stringValue = draft.urlText

        notesView.string = draft.notes
        notesView.font = .systemFont(ofSize: 12)
        notesView.isRichText = false
        notesView.allowsUndo = true
        notesView.textContainerInset = NSSize(width: 2, height: 4)
        let notesScroll = NSScrollView()
        notesScroll.documentView = notesView
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        notesView.autoresizingMask = [.width]
        notesView.isVerticallyResizable = true
        notesView.textContainer?.widthTracksTextView = true
        notesScroll.heightAnchor.constraint(equalToConstant: 70).isActive = true

        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.alignment = .right
            l.textColor = .secondaryLabelColor
            return l
        }
        let grid = NSGridView(views: [
            [label("Title"), titleField],
            [NSGridCell.emptyContentView, allDay],
            [label("Starts"), startPicker],
            [label("Ends"), endPicker],
            [label("Calendar"), calendarPopup],
            [label("Location"), locationField],
            [label("URL"), urlField],
            [label("Notes"), notesScroll],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.row(at: 7).yPlacement = .top
        grid.columnSpacing = 8
        grid.rowSpacing = 8
        titleField.widthAnchor.constraint(equalToConstant: 250).isActive = true

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.isHidden = true
        errorLabel.preferredMaxLayoutWidth = 310

        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .push
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isHidden = draft.isNew || !editable
        if !editable {
            saveButton.isHidden = true
            cancelButton.title = "Close"
            cancelButton.keyEquivalent = "\r"
            [titleField, locationField, urlField].forEach { $0.isEditable = false }
            [allDay, startPicker, endPicker, calendarPopup].forEach { $0.isEnabled = false }
            notesView.isEditable = false
        }

        let buttons = NSStackView(views: [deleteButton, NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [grid, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        view = stack
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if editable { view.window?.makeFirstResponder(titleField) }
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
                item.image = Self.swatch(NSColor(rgba: c.color))
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

    static func swatch(_ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            color.setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).fill()
            return true
        }
        return img
    }

    private func updatePickerElements() {
        let elements: NSDatePicker.ElementFlags = allDay.state == .on ? [.yearMonthDay] : [.yearMonthDay, .hourMinute]
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
        d.isAllDay = allDay.state == .on
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

    @objc private func cancelClicked() { finish?(.cancelled) }

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
