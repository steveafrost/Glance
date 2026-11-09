import CoreGraphics

/// How tall the agenda below the grid may be. The grid shows only the
/// month's own 4 to 6 weeks, and the agenda gets the rows a shorter month
/// frees, so with a full agenda the grid plus agenda is the same height
/// every month and the window doesn't change size between months.
public enum AgendaSizing {
    /// The agenda's maximum height under a full 6-row grid.
    public static let baseMaxHeight: CGFloat = 420
    /// The least the agenda shrinks to when the screen is short.
    public static let minimumScreenRoom: CGFloat = 60

    /// The agenda's maximum: the base plus the height of the rows the grid
    /// doesn't use.
    public static func maxHeight(for geometry: GridGeometry, base: CGFloat = baseMaxHeight) -> CGFloat {
        base + CGFloat(MonthGrid.rows - geometry.rows) * geometry.cellHeight
    }

    /// The agenda's height: its content (at least `minimum`, so an empty
    /// agenda still shows a row), capped at `maxHeight(for:)` and, when
    /// given, at the room left on screen (never below `minimumScreenRoom`).
    /// The agenda scrolls beyond this.
    public static func height(content: CGFloat, minimum: CGFloat, geometry: GridGeometry,
                              screenRoom: CGFloat? = nil, base: CGFloat = baseMaxHeight) -> CGFloat {
        var cap = maxHeight(for: geometry, base: base)
        if let screenRoom { cap = min(cap, max(minimumScreenRoom, screenRoom)) }
        return min(max(content, minimum), cap)
    }
}
