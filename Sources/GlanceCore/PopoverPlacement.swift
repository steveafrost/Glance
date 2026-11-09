import CoreGraphics
import Foundation

/// Where to put the calendar window, following Itsycal's rules:
/// centred under the status item, kept 10pt from the screen edges, on the
/// display that owns the item (even while that display's menu bar is
/// hidden), and falling back to the screen's top-right corner when the item
/// is off screen or hidden behind app menus.
public enum PopoverPlacement {
    public static let edgeMargin: CGFloat = 10
    public static let gapBelowItem: CGFloat = 2

    public struct Screen: Equatable, Sendable {
        public var frame: CGRect
        public var visibleFrame: CGRect
        public init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    public struct Input: Sendable {
        /// Status item button frame in screen coordinates, if it has a window.
        public var itemFrame: CGRect?
        /// Whether the item's window is currently visible (not occluded).
        public var itemVisible: Bool
        public var screens: [Screen]
        /// Index into `screens` of the main screen, used as a last resort.
        public var mainScreenIndex: Int
        public var windowSize: CGSize
        /// True when the window is being shown; false for repositioning while open.
        public var initialPresentation: Bool
        public var alwaysTopRight: Bool
        /// Fallback state from the previous placement while the window stays open.
        public var previous: Result?

        public init(itemFrame: CGRect?, itemVisible: Bool, screens: [Screen], mainScreenIndex: Int = 0,
                    windowSize: CGSize, initialPresentation: Bool, alwaysTopRight: Bool = false,
                    previous: Result? = nil) {
            self.itemFrame = itemFrame
            self.itemVisible = itemVisible
            self.screens = screens
            self.mainScreenIndex = mainScreenIndex
            self.windowSize = windowSize
            self.initialPresentation = initialPresentation
            self.alwaysTopRight = alwaysTopRight
            self.previous = previous
        }
    }

    public struct Result: Equatable, Sendable {
        /// Window frame origin (bottom-left) in screen coordinates.
        public var origin: CGPoint
        /// Arrow centre in window coordinates; nil when there is no arrow.
        public var arrowX: CGFloat?
        public var usesFallback: Bool
        public var anchor: CGRect
        public var screenFrame: CGRect
        /// Tallest the window may be without leaving the screen.
        public var maxHeight: CGFloat
    }

    /// The screen that owns a status item. A hidden menu bar parks items
    /// just above their screen, so probe a point below the item.
    public static func screenIndex(for itemFrame: CGRect, in screens: [Screen]) -> Int? {
        let probe = CGPoint(x: itemFrame.midX, y: itemFrame.minY - 100)
        return screens.firstIndex { $0.frame.contains(probe) }
    }

    public static func place(_ input: Input, arrowHalfWidth: CGFloat = 13, cornerRadius: CGFloat = 16) -> Result? {
        guard !input.screens.isEmpty else { return nil }
        var anchor = input.itemFrame ?? .zero
        var screenIdx = input.itemFrame.flatMap { screenIndex(for: $0, in: input.screens) }
        var fallback = screenIdx == nil || input.alwaysTopRight

        // An item covered by app menus, or hidden with a full-screen app's
        // menu bar, is not a useful anchor when first showing the window.
        // An auto-hiding menu bar parks the item above the screen, where it
        // reads as not visible, yet its x position is still a good anchor.
        if input.initialPresentation, !fallback, let i = screenIdx,
           anchor.minY < input.screens[i].frame.maxY, !input.itemVisible {
            fallback = true
        }

        // Once in the fallback position, stay there while open, unless the
        // screen it is on has gone away or changed size.
        if !input.initialPresentation, let prev = input.previous, prev.usesFallback,
           let i = input.screens.firstIndex(where: { $0.frame == prev.screenFrame }) {
            screenIdx = i
            anchor = prev.anchor
            fallback = true
        } else if fallback {
            let i = screenIdx ?? min(max(input.mainScreenIndex, 0), input.screens.count - 1)
            screenIdx = i
            let s = input.screens[i]
            anchor = CGRect(x: s.frame.maxX, y: s.visibleFrame.maxY, width: 0, height: 0)
        }

        let screen = input.screens[screenIdx ?? 0]
        anchor.origin.y = min(anchor.origin.y, screen.frame.maxY)

        let w = input.windowSize.width
        var x = (anchor.midX - w / 2).rounded()
        x = min(x, screen.frame.maxX - w - edgeMargin)
        x = max(x, screen.frame.minX + edgeMargin)
        let top = anchor.minY - gapBelowItem
        let maxHeight = max(0, top - (screen.visibleFrame.minY + edgeMargin))
        let h = min(input.windowSize.height, maxHeight)

        var arrowX: CGFloat? = anchor.midX - x
        if fallback { arrowX = nil }
        if let a = arrowX, a - arrowHalfWidth < cornerRadius || a + arrowHalfWidth > w - cornerRadius {
            arrowX = nil
        }

        return Result(origin: CGPoint(x: x, y: top - h), arrowX: arrowX, usesFallback: fallback,
                      anchor: anchor, screenFrame: screen.frame, maxHeight: maxHeight)
    }
}
