import AppKit
import GlanceCore

/// Header + grid + agenda, laid out by hand (no Auto Layout on month change).
@MainActor
final class CalendarContentView: NSView {
    let monthLabel = NSTextField(labelWithString: "")
    let prevButton = CalendarContentView.iconButton("chevron.left", "Previous month")
    let todayButton = CalendarContentView.iconButton("circle", "Today")
    let nextButton = CalendarContentView.iconButton("chevron.right", "Next month")
    let addButton = CalendarContentView.iconButton("plus", "New event")
    let menuButton = CalendarContentView.iconButton("ellipsis.circle", "Options")
    let grid: MonthGridView
    let divider = NSView()
    let agenda = AgendaView()
    let accessView = AccessMessageView()

    static let headerHeight: CGFloat = 30
    static let gapAboveDivider: CGFloat = 6
    static let gapBelowDivider: CGFloat = 4

    var agendaHeight: CGFloat = 0 { didSet { needsLayout = true } }
    var showsAccessMessage = false {
        didSet {
            accessView.isHidden = !showsAccessMessage
            agenda.isHidden = showsAccessMessage
            needsLayout = true
        }
    }

    init(grid: MonthGridView) {
        self.grid = grid
        super.init(frame: .zero)
        monthLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        monthLabel.lineBreakMode = .byTruncatingTail
        divider.wantsLayer = true
        accessView.isHidden = true
        [monthLabel, prevButton, todayButton, nextButton, addButton, menuButton, grid, divider, agenda, accessView].forEach(addSubview)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static func iconButton(_ symbol: String, _ label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        let b = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        b.isBordered = false
        b.toolTip = label
        b.setAccessibilityLabel(label)
        return b
    }

    func apply(_ colors: ThemeColors) {
        monthLabel.textColor = colors.primaryText
        [prevButton, todayButton, nextButton, addButton, menuButton].forEach { $0.contentTintColor = colors.secondaryText }
        divider.layer?.backgroundColor = colors.divider.cgColor
        accessView.apply(colors)
        grid.colors = colors
        agenda.colors = colors
    }

    var accessHeight: CGFloat { 110 }

    /// Total height for the current grid and agenda height.
    var preferredHeight: CGFloat {
        let lower = showsAccessMessage ? accessHeight : agendaHeight
        return Self.headerHeight + grid.model.geometry.size.height + Self.gapAboveDivider + 1 + Self.gapBelowDivider + lower
    }

    var preferredWidth: CGFloat { grid.model.geometry.size.width }

    /// Height of everything except the agenda.
    var fixedHeight: CGFloat {
        Self.headerHeight + grid.model.geometry.size.height + Self.gapAboveDivider + 1 + Self.gapBelowDivider
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let bs: CGFloat = 19
        var x = w
        for b in [menuButton, nextButton, todayButton, prevButton, addButton] {
            x -= bs
            b.frame = CGRect(x: x, y: 4, width: bs, height: bs)
            if b === prevButton { x -= 2 }
        }
        monthLabel.frame = CGRect(x: 6, y: 6, width: x - 8, height: 20)
        let gs = grid.model.geometry.size
        grid.frame = CGRect(x: ((w - gs.width) / 2).rounded(), y: Self.headerHeight, width: gs.width, height: gs.height)
        let dividerY = grid.frame.maxY + Self.gapAboveDivider
        divider.frame = CGRect(x: 4, y: dividerY, width: w - 8, height: 1)
        let lowerY = dividerY + 1 + Self.gapBelowDivider
        agenda.frame = CGRect(x: 0, y: lowerY, width: w, height: max(0, bounds.height - lowerY))
        accessView.frame = agenda.frame
    }
}

/// Explains missing calendar access, with a button that fixes it.
@MainActor
final class AccessMessageView: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    let button = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        button.bezelStyle = .push
        addSubview(label)
        addSubview(button)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func apply(_ colors: ThemeColors) { label.textColor = colors.secondaryText }

    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = bounds.width - 16
        let h = label.intrinsicContentSize.height
        label.frame = CGRect(x: 8, y: 8, width: bounds.width - 16, height: h)
        button.sizeToFit()
        button.frame.origin = CGPoint(x: ((bounds.width - button.frame.width) / 2).rounded(), y: label.frame.maxY + 10)
    }
}
