import AppKit
import QuartzCore

/// A borderless, non-activating panel shaped like a popover: a rounded
/// body with an arrow pointing at the status item.
@MainActor
final class PopoverWindow: NSPanel {
    static let arrowHeight: CGFloat = 8
    static let cornerRadius: CGFloat = 16
    static let padding: CGFloat = 8

    let frameView = PopoverFrameView()
    /// Called for keys nothing else handled (the grid gets first chance).
    var onCancel: (() -> Void)?

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
    var arrowX: CGFloat? { didSet { needsLayout = true } }
    var fillColor: NSColor = .windowBackgroundColor { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.mask = shape
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = Self.path(in: bounds, arrowX: arrowX)
        CATransaction.commit()
        window?.invalidateShadow()
    }

    /// Body plus arrow as one path, so the mask (and the system shadow) has no seam.
    static func path(in bounds: CGRect, arrowX: CGFloat?) -> CGPath {
        let h = PopoverWindow.arrowHeight, r = PopoverWindow.cornerRadius
        let body = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height - h)
        let path = CGMutablePath()
        path.addRoundedRect(in: body, cornerWidth: r, cornerHeight: r)
        if let x = arrowX {
            let curve: CGFloat = 5
            let top = body.maxY
            path.move(to: CGPoint(x: x - h - curve, y: top - 1))
            path.addLine(to: CGPoint(x: x - h - curve, y: top))
            path.addCurve(to: CGPoint(x: x, y: top + h),
                          control1: CGPoint(x: x - h, y: top), control2: CGPoint(x: x - curve * 0.6, y: top + h))
            path.addCurve(to: CGPoint(x: x + h + curve, y: top),
                          control1: CGPoint(x: x + curve * 0.6, y: top + h), control2: CGPoint(x: x + h, y: top))
            path.addLine(to: CGPoint(x: x + h + curve, y: top - 1))
            path.closeSubpath()
        }
        return path
    }
}
