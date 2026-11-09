import AppKit

/// AppKit controls drawn from the Catppuccin theme instead of system
/// chrome: filled fields with a hairline border and an accent focus ring,
/// accent primary buttons, and a themed checkbox.

/// A rounded surface0 box with a 1px surface1 border around a field. When
/// anything inside it is first responder the border becomes a 2px accent ring.
@MainActor
final class ThemedFieldBox: NSView {
    let content: NSView
    private let topInset: CGFloat
    var colors: ThemeColors? { didSet { needsDisplay = true } }
    var focused = false { didSet { if focused != oldValue { needsDisplay = true } } }

    init(_ content: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 3, left: 7, bottom: 3, right: 7), height: CGFloat? = 26) {
        self.content = content
        self.topInset = insets.top
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
        if let height { heightAnchor.constraint(equalToConstant: height).isActive = true }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let c = colors else { return }
        layer?.backgroundColor = c.surface0.cgColor
        layer?.borderColor = (focused ? c.controlAccent : c.surface1).cgColor
        layer?.borderWidth = focused ? 2 : 1
    }

    /// Text baseline alignment in grids: use the field's baseline.
    override var firstBaselineOffsetFromTop: CGFloat {
        content.firstBaselineOffsetFromTop + topInset
    }
}

/// A borderless text field for use inside a `ThemedFieldBox`.
@MainActor
func themedTextField(placeholder: String, colors: ThemeColors, font: NSFont = .systemFont(ofSize: 13)) -> NSTextField {
    let f = NSTextField()
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.font = font
    f.lineBreakMode = .byTruncatingTail
    f.usesSingleLineMode = true
    f.cell?.isScrollable = true
    applyText(colors, to: f, placeholder: placeholder)
    return f
}

@MainActor
func applyText(_ c: ThemeColors, to f: NSTextField, placeholder: String) {
    f.textColor = c.primaryText
    f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
        .foregroundColor: c.otherMonthText, .font: f.font ?? .systemFont(ofSize: 13),
    ])
}

/// A filled push button: `.primary` (accent fill, base text), `.secondary`
/// (surface0 fill, text), or `.destructive` (red text, no fill).
@MainActor
final class ThemedButton: NSButton {
    enum Kind { case primary, secondary, destructive }
    let kind: Kind
    var colors: ThemeColors? { didSet { restyle() } }
    /// Skip the key equivalent while a text view is editing (so ⌘⌫ still
    /// deletes text in a field).
    var keyEquivalentSkipsTextEditing = false

    init(title: String, kind: Kind, target: AnyObject?, action: Selector?) {
        self.kind = kind
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = attributedTitle.size()
        return NSSize(width: max(72, ceil(s.width) + 28), height: 26)
    }

    override var isEnabled: Bool { didSet { restyle() } }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentSkipsTextEditing, window?.firstResponder is NSText { return false }
        return super.performKeyEquivalent(with: event)
    }

    private func restyle() {
        guard let c = colors else { return }
        let fg: NSColor = switch kind {
        case .primary: c.onAccent
        case .secondary: c.primaryText
        case .destructive: c.destructive
        }
        let weight: NSFont.Weight = kind == .primary ? .semibold : .regular
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: isEnabled ? fg : fg.withAlphaComponent(0.45),
            .font: NSFont.systemFont(ofSize: 13, weight: weight),
        ])
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let c = colors else { return }
        let pressed = cell?.isHighlighted == true
        var fill: NSColor = switch kind {
        case .primary: c.controlAccent
        case .secondary: c.surface0
        case .destructive: .clear
        }
        if !isEnabled { fill = fill.withAlphaComponent(fill.alphaComponent * 0.5) }
        if pressed { fill = kind == .destructive ? c.destructive.withAlphaComponent(0.15) : fill.blended(withFraction: 0.18, of: c.isDark ? .white : .black) ?? fill }
        layer?.backgroundColor = fill.cgColor
        layer?.borderWidth = kind == .secondary ? 1 : 0
        layer?.borderColor = c.surface1.cgColor
    }
}

/// A checkbox drawn in theme colours: an accent box with a base-coloured
/// tick when on, a surface0 box with a surface1 border when off.
@MainActor
final class ThemedCheckbox: NSControl {
    var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }
    var colors: ThemeColors? { didSet { needsDisplay = true } }
    private let labelFont = NSFont.systemFont(ofSize: 13)

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        focusRingType = .exterior
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: labelFont]).width
        return NSSize(width: ceil(18 + 6 + w), height: 20)
    }

    override var firstBaselineOffsetFromTop: CGFloat { (20 - labelFont.capHeight) / 2 + labelFont.capHeight }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: boxRect, xRadius: 4, yRadius: 4).fill() }
    override var focusRingMaskBounds: NSRect { boxRect }

    private var boxRect: NSRect { NSRect(x: 1, y: (bounds.height - 16) / 2, width: 16, height: 16) }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = colors else { return }
        let alpha: CGFloat = isEnabled ? 1 : 0.5
        let box = NSBezierPath(roundedRect: boxRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        if isOn {
            c.controlAccent.withAlphaComponent(alpha).setFill()
            box.fill()
            let tick = NSBezierPath()
            let r = boxRect
            tick.move(to: NSPoint(x: r.minX + 4, y: r.midY))
            tick.line(to: NSPoint(x: r.minX + 7, y: r.minY + 4.5))
            tick.line(to: NSPoint(x: r.maxX - 3.5, y: r.maxY - 4))
            tick.lineWidth = 2
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            c.onAccent.setStroke()
            tick.stroke()
        } else {
            c.surface0.withAlphaComponent(alpha).setFill()
            box.fill()
            c.surface1.setStroke()
            box.lineWidth = 1
            box.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: c.primaryText.withAlphaComponent(alpha)]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: 24, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { toggle() } else { super.keyDown(with: event) }
    }

    private func toggle() {
        isOn.toggle()
        sendAction(action, to: target)
    }
}

/// A field editor with the theme's caret and selection colours.
@MainActor
func themedFieldEditor(_ c: ThemeColors) -> NSTextView {
    let t = NSTextView()
    t.isFieldEditor = true
    style(textView: t, c)
    return t
}

@MainActor
func style(textView t: NSTextView, _ c: ThemeColors) {
    t.insertionPointColor = c.controlAccent
    t.selectedTextAttributes = [.backgroundColor: c.controlAccent.withAlphaComponent(0.3), .foregroundColor: c.primaryText]
    t.textColor = c.primaryText
    t.drawsBackground = false
}
