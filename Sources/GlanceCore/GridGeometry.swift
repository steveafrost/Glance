import CoreGraphics
import Foundation

/// Cell layout for the month grid, in a flipped (top-left origin) view.
public struct GridGeometry: Equatable, Sendable {
    public var cellWidth: CGFloat
    public var cellHeight: CGFloat
    public var headerHeight: CGFloat
    public var weekColumnWidth: CGFloat
    public var showsWeekNumbers: Bool

    public init(cellWidth: CGFloat = 33, cellHeight: CGFloat = 28, headerHeight: CGFloat = 20,
                weekColumnWidth: CGFloat = 24, showsWeekNumbers: Bool = false) {
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.headerHeight = headerHeight
        self.weekColumnWidth = weekColumnWidth
        self.showsWeekNumbers = showsWeekNumbers
    }

    public var gridOriginX: CGFloat { showsWeekNumbers ? weekColumnWidth : 0 }

    public var size: CGSize {
        CGSize(width: gridOriginX + cellWidth * CGFloat(MonthGrid.columns),
               height: headerHeight + cellHeight * CGFloat(MonthGrid.rows))
    }

    public func cellRect(index: Int) -> CGRect {
        let row = index / MonthGrid.columns, col = index % MonthGrid.columns
        return CGRect(x: gridOriginX + CGFloat(col) * cellWidth,
                      y: headerHeight + CGFloat(row) * cellHeight,
                      width: cellWidth, height: cellHeight)
    }

    public func headerRect(column: Int) -> CGRect {
        CGRect(x: gridOriginX + CGFloat(column) * cellWidth, y: 0, width: cellWidth, height: headerHeight)
    }

    public func weekNumberRect(row: Int) -> CGRect? {
        guard showsWeekNumbers else { return nil }
        return CGRect(x: 0, y: headerHeight + CGFloat(row) * cellHeight, width: weekColumnWidth, height: cellHeight)
    }

    /// The day column band (header plus all rows), for weekday highlighting.
    public func columnRect(column: Int) -> CGRect {
        CGRect(x: gridOriginX + CGFloat(column) * cellWidth, y: 0,
               width: cellWidth, height: size.height)
    }

    public func index(at point: CGPoint) -> Int? {
        let x = point.x - gridOriginX, y = point.y - headerHeight
        guard x >= 0, y >= 0 else { return nil }
        let col = Int(x / cellWidth), row = Int(y / cellHeight)
        guard col < MonthGrid.columns, row < MonthGrid.rows else { return nil }
        return row * MonthGrid.columns + col
    }
}

/// Keyboard handling for the grid, mirroring Itsycal: ←/→ change month,
/// ↑/↓ change year, ⇧-arrows (or h/j/k/l) move the selected day, Space
/// jumps to today, Return adds an event on the selected day, Esc closes.
public enum GridCommand: Equatable, Sendable {
    case moveDays(Int)
    case moveMonths(Int)
    case today
    case newEvent
    case close
    case openSettings
    case joinMeeting
    case toggleWeekNumbers
}

public enum GridKey: Equatable, Sendable {
    case left, right, up, down, returnKey, escape, space
    case character(Character)
}

public struct GridModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = GridModifiers(rawValue: 1)
    public static let command = GridModifiers(rawValue: 2)
    public static let option = GridModifiers(rawValue: 4)
    public static let control = GridModifiers(rawValue: 8)
}

public enum GridNavigation {
    public static func command(for key: GridKey, modifiers m: GridModifiers) -> GridCommand? {
        switch (key, m) {
        case (.left, []): .moveMonths(-1)
        case (.right, []): .moveMonths(1)
        case (.up, []): .moveMonths(-12)
        case (.down, []): .moveMonths(12)
        case (.left, .shift), (.character("h"), []): .moveDays(-1)
        case (.right, .shift), (.character("l"), []): .moveDays(1)
        case (.up, .shift), (.character("k"), []): .moveDays(-7)
        case (.down, .shift), (.character("j"), []): .moveDays(7)
        case (.character("H"), .shift): .moveMonths(-1)
        case (.character("L"), .shift): .moveMonths(1)
        case (.character("K"), .shift): .moveMonths(-12)
        case (.character("J"), .shift): .moveMonths(12)
        case (.space, []), (.character("t"), []): .today
        case (.returnKey, []), (.character("n"), .command): .newEvent
        case (.escape, []): .close
        case (.character(","), .command): .openSettings
        case (.character("j"), .command): .joinMeeting
        case (.character("w"), []): .toggleWeekNumbers
        default: nil
        }
    }

    /// Selection after moving by months: same day number, clamped to the month's length.
    public static func day(_ day: DayKey, movedByMonths n: Int) -> DayKey {
        let m = day.monthKey.adding(months: n)
        return DayKey(year: m.year, month: m.month, day: min(day.day, m.numberOfDays))
    }
}
