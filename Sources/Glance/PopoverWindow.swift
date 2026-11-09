import AppKit
import QuartzCore
import GlanceCore

/// A borderless, non-activating panel shaped like a popover: a rounded
/// body with an arrow pointing at the status item.
@MainActor
final class PopoverWindow: NSPanel {
    static let arrowHeight: CGFloat = PopoverShape.arrowHeight
    static let cornerRadius: CGFloat = 16
    static let padding: CGFloat = 8

    let frameView = PopoverFrameView()
    /// Called for keys nothing else handled (the grid gets first chance).
    var onCancel: (() -> Void)?
    /// A themed field editor for text fields in this panel.
    var fieldEditorOverride: NSTextView?

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .mainMenu
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
        contentView = frameView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if let f = fieldEditorOverride, object is NSTextField { return f }
        return super.fieldEditor(createFlag, for: object)
    }

    /// Size of the content area (inside padding and arrow) for a window size.
    static func windowSize(forContent size: CGSize) -> CGSize {
        CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding + arrowHeight)
    }

    var contentRect: CGRect {
        let b = frameView.bounds
        return CGRect(x: Self.padding, y: Self.padding,
                      width: b.width - 2 * Self.padding, height: b.height - 2 * Self.padding - Self.arrowHeight)
    }
}

@MainActor
final class PopoverFrameView: NSView {
    private let shape = CAShapeLayer()
    private let border = CAShapeLayer()
    /// Arrow apex along the top edge (window x); nil hides the arrow.
    var arrowX: CGFloat? {
        get { arrow?.edge == .top ? arrow?.position : nil }
        set { arrow = newValue.map { PopoverShape.Arrow(edge: .top, position: $0) } }
    }
    var arrow: PopoverShape.Arrow? { didSet { needsLayout = true } }
    var fillColor: NSColor = .windowBackgroundColor { didSet { needsDisplay = true } }
    var borderColor: NSColor = .clear { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.mask = shape
        border.fillColor = nil
        border.lineWidth = 2 // half of it is clipped by the mask: a 1pt inner hairline
        border.zPosition = 1000
        layer?.addSublayer(border)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
        border.strokeColor = borderColor.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = PopoverShape.path(in: bounds, arrow: arrow, cornerRadius: PopoverWindow.cornerRadius)
        shape.frame = bounds
        shape.path = path
        border.frame = bounds
        border.path = path
        CATransaction.commit()
        window?.invalidateShadow()
    }
}
