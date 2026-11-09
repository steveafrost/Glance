import AppKit
import GlanceCore

/// The agenda list: a view-based table with reused cells and manual cell layout.
@MainActor
final class AgendaView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = AgendaTableView()
    private(set) var rows: [AgendaRow] = []
    var colors: ThemeColors? { didSet { table.reloadData() } }
    var activeMeetingID: String? { didSet { if activeMeetingID != oldValue { table.reloadData() } } }
    var calendar = Calendar.autoupdatingCurrent
    var today = DayKey(date: Date(), calendar: .autoupdatingCurrent)

    var onEdit: ((EventSnapshot) -> Void)?
    var onJoin: ((EventSnapshot) -> Void)?
    var onDelete: ((EventSnapshot) -> Void)?
    var onOpenInCalendar: ((EventSnapshot) -> Void)?

    static let dayRowHeight: CGFloat = 24
    static let eventRowHeight: CGFloat = 38
    static let emptyRowHeight: CGFloat = 26
    static let maxHeight: CGFloat = 420

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        borderType = .noBorder
        let column = NSTableColumn(identifier: .init("main"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.style = .plain
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.menuProvider = { [weak self] row in self?.menu(forRow: row) }
        documentView = table
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setRows(_ rows: [AgendaRow]) {
        guard rows != self.rows else { return }
        self.rows = rows
        table.reloadData()
    }

    /// Height needed to show every row without scrolling.
    var contentHeight: CGFloat {
        rows.reduce(0) { $0 + Self.height(of: $1) }
    }

    static func height(of row: AgendaRow) -> CGFloat {
        switch row {
        case .day: dayRowHeight
        case .event: eventRowHeight
        case .noEvents: emptyRowHeight
        }
    }

    override func layout() {
        super.layout()
        table.tableColumns.first?.width = contentSize.width
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Self.height(of: rows[row]) }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let v = tableView.makeView(withIdentifier: AgendaRowView.id, owner: nil) as? AgendaRowView ?? AgendaRowView()
        v.identifier = AgendaRowView.id
        v.colors = colors
        v.isEventRow = if case .event = rows[row] { true } else { false }
        return v
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colors else { return nil }
        switch rows[row] {
        case .day(let day):
            let v = tableView.makeView(withIdentifier: DayHeaderCell.id, owner: nil) as? DayHeaderCell ?? DayHeaderCell()
            v.configure(day: day, today: today, calendar: calendar, colors: colors, isFirst: row == 0)
            return v
        case .noEvents:
            let v = tableView.makeView(withIdentifier: NoEventsCell.id, owner: nil) as? NoEventsCell ?? NoEventsCell()
            v.configure(colors: colors)
            return v
        case .event(let e, let day):
            let v = tableView.makeView(withIdentifier: EventCell.id, owner: nil) as? EventCell ?? EventCell()
            let time = Agenda.timeText(for: e, on: day, calendar: calendar, locale: .autoupdatingCurrent)
            v.configure(event: e, time: time, colors: colors, isActiveMeeting: e.id == activeMeetingID,
                        isPast: e.end < Date() && !EventBucketing.treatsAsAllDay(e, on: day, calendar: calendar))
            v.onJoin = { [weak self] in self?.onJoin?(e) }
            return v
        }
    }

    // MARK: Actions

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count, case .event(let e, _) = rows[row] else { return }
        onEdit?(e)
    }

    private func menu(forRow row: Int) -> NSMenu? {
        guard row >= 0, row < rows.count, case .event(let e, _) = rows[row] else { return nil }
        let menu = NSMenu()
        func add(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, action: action)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        add(e.isEditable ? "Edit…" : "Show Details…") { [weak self] in self?.onEdit?(e) }
        if e.meetingURL != nil {
            add("Join Meeting") { [weak self] in self?.onJoin?(e) }
            add("Copy Meeting Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e.meetingURL?.absoluteString ?? "", forType: .string)
            }
        }
        add("Open in Calendar") { [weak self] in self?.onOpenInCalendar?(e) }
        menu.addItem(.separator())
        add("Delete…", enabled: e.isEditable) { [weak self] in self?.onDelete?(e) }
        return menu
    }
}

/// NSMenuItem that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

@MainActor
final class AgendaTableView: NSTableView {
    var menuProvider: ((Int) -> NSMenu?)?
    private var hoveredRow = -1

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return menuProvider?(row)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        setHovered(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) { setHovered(-1) }

    private func setHovered(_ row: Int) {
        guard row != hoveredRow else { return }
        if hoveredRow >= 0, hoveredRow < numberOfRows { (rowView(atRow: hoveredRow, makeIfNecessary: false) as? AgendaRowView)?.isHovered = false }
        hoveredRow = row
        if row >= 0 { (rowView(atRow: row, makeIfNecessary: false) as? AgendaRowView)?.isHovered = true }
    }

    override func reloadData() {
        hoveredRow = -1
        super.reloadData()
    }
}

@MainActor
final class AgendaRowView: NSTableRowView {
    static let id = NSUserInterfaceItemIdentifier("AgendaRow")
    var colors: ThemeColors?
    var isEventRow = false
    var isHovered = false { didSet { needsDisplay = true } }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, isEventRow, let colors else { return }
        colors.hover.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }
}

@MainActor
final class DayHeaderCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("DayHeader")
    private let label = NSTextField(labelWithString: "")
    private let divider = NSView()
    private var showsDivider = false

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        divider.wantsLayer = true
        addSubview(label)
        addSubview(divider)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()

    func configure(day: DayKey, today: DayKey, calendar: Calendar, colors: ThemeColors, isFirst: Bool) {
        let date = day.startDate(in: calendar)
        var text = Self.formatter.string(from: date).uppercased()
        switch today.days(until: day) {
        case 0: text = "TODAY · " + text
        case 1: text = "TOMORROW · " + text
        case -1: text = "YESTERDAY · " + text
        default: break
        }
        label.stringValue = text
        label.textColor = colors.secondaryText
        divider.layer?.backgroundColor = colors.divider.cgColor
        showsDivider = !isFirst
        divider.isHidden = !showsDivider
        needsLayout = true
    }

    override func layout() {
        super.layout()
        divider.frame = CGRect(x: 6, y: bounds.height - 1, width: bounds.width - 12, height: 1)
        label.frame = CGRect(x: 6, y: 3, width: bounds.width - 12, height: 15)
    }
}

@MainActor
final class NoEventsCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("NoEvents")
    private let label = NSTextField(labelWithString: "No events")

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        label.font = .systemFont(ofSize: 12)
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(colors: ThemeColors) { label.textColor = colors.otherMonthText }

    override func layout() {
        super.layout()
        label.frame = CGRect(x: 20, y: 5, width: bounds.width - 26, height: 16)
    }
}

@MainActor
final class EventCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("Event")
    private let dot = NSView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let join = NSButton()
    var onJoin: (() -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 11)
        detail.lineBreakMode = .byTruncatingTail
        join.bezelStyle = .badge
        join.isBordered = false
        join.imagePosition = .imageOnly
        join.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Join meeting")
        join.target = self
        join.action = #selector(joinClicked)
        join.toolTip = "Join meeting"
        [dot, title, detail, join].forEach(addSubview)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(event e: EventSnapshot, time: String, colors: ThemeColors, isActiveMeeting: Bool, isPast: Bool) {
        dot.layer?.backgroundColor = NSColor(rgba: e.color).cgColor
        title.stringValue = e.title
        title.textColor = isPast ? colors.secondaryText : colors.primaryText
        var parts = [time]
        if let loc = e.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty,
           MeetingLinkParser.firstLink(in: loc) == nil {
            parts.append(loc)
        }
        detail.stringValue = parts.joined(separator: " · ")
        detail.textColor = colors.secondaryText
        join.isHidden = e.meetingURL == nil
        if let url = e.meetingURL, let p = MeetingLinkParser.classify(url)?.provider {
            join.toolTip = "Join \(p.displayName) meeting"
            join.setAccessibilityLabel("Join \(p.displayName) meeting")
        }
        join.contentTintColor = isActiveMeeting ? colors.meeting : colors.secondaryText
        alphaValue = isPast ? 0.7 : 1
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let joinW: CGFloat = join.isHidden ? 0 : 28
        dot.frame = CGRect(x: 8, y: bounds.height - 15, width: 7, height: 7)
        let textW = bounds.width - 22 - joinW - 6
        title.frame = CGRect(x: 22, y: bounds.height - 20, width: textW, height: 17)
        detail.frame = CGRect(x: 22, y: 4, width: textW, height: 14)
        join.frame = CGRect(x: bounds.width - joinW - 4, y: (bounds.height - 24) / 2, width: joinW, height: 24)
    }

    @objc private func joinClicked() { onJoin?() }
}
